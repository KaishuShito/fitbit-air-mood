import Foundation
import Testing
@testable import FitbitAirMoodBar

struct TaskLineClassifierTests {
    @Test
    func classifiesHeadings() {
        #expect(TaskLineClassifier.classify("# TASKS") == .heading(level: 1))
        #expect(TaskLineClassifier.classify("## 今日") == .heading(level: 2))
        #expect(TaskLineClassifier.classify("### deep") == .heading(level: 3))
        #expect(TaskLineClassifier.classify("#not-a-heading") == .body)
    }

    @Test
    func classifiesCheckboxes() {
        #expect(TaskLineClassifier.classify("- [ ] task") == .checkbox(checked: false, markerLength: 6))
        #expect(TaskLineClassifier.classify("- [x] done") == .checkbox(checked: true, markerLength: 6))
        #expect(TaskLineClassifier.classify("- [X] done") == .checkbox(checked: true, markerLength: 6))
        #expect(TaskLineClassifier.classify("  - [ ] nested") == .checkbox(checked: false, markerLength: 8))
    }

    @Test
    func classifiesBulletsSeparatorsAndBody() {
        #expect(TaskLineClassifier.classify("- plain bullet") == .bullet(markerLength: 2))
        #expect(TaskLineClassifier.classify("---") == .separator)
        #expect(TaskLineClassifier.classify("次の予定: 昼") == .body)
        #expect(TaskLineClassifier.classify("") == .body)
    }
}

struct TaskCheckboxTogglerTests {
    @Test
    func togglesUncheckedToChecked() {
        let result = TaskCheckboxToggler.toggle(text: "- [ ] task\n", selectionLocation: 8)
        #expect(result?.text == "- [x] task\n")
        #expect(result?.selectionLocation == 8)
    }

    @Test
    func togglesCheckedToUnchecked() {
        let result = TaskCheckboxToggler.toggle(text: "- [x] done", selectionLocation: 3)
        #expect(result?.text == "- [ ] done")
    }

    @Test
    func promotesBulletAndPlainLines() {
        #expect(TaskCheckboxToggler.toggledLine("- idea") == "- [ ] idea")
        #expect(TaskCheckboxToggler.toggledLine("call Yota") == "- [ ] call Yota")
        #expect(TaskCheckboxToggler.toggledLine("  indented") == "  - [ ] indented")
        #expect(TaskCheckboxToggler.toggledLine("") == "- [ ] ")
    }

    @Test
    func leavesHeadingsAndSeparatorsAlone() {
        #expect(TaskCheckboxToggler.toggledLine("## 今日") == nil)
        #expect(TaskCheckboxToggler.toggledLine("---") == nil)
    }

    @Test
    func editTargetsOnlyTheCaretLine() {
        let text = "## 今日\n- [ ] one\n- [ ] two\n"
        // Caret inside "one" (line starts at offset 6 in UTF-16).
        let caret = 6 + 8
        let edit = TaskCheckboxToggler.edit(text: text, selectionLocation: caret)
        #expect(edit?.replacement == "- [x] one")
        #expect(edit?.range == NSRange(location: 6, length: 9))
        let result = TaskCheckboxToggler.toggle(text: text, selectionLocation: caret)
        #expect(result?.text == "## 今日\n- [x] one\n- [ ] two\n")
    }

    @Test
    func promotionKeepsCaretInsideLine() {
        let result = TaskCheckboxToggler.toggle(text: "task", selectionLocation: 2)
        #expect(result?.text == "- [ ] task")
        #expect(result?.selectionLocation == 8)
    }
}

struct JournalConfigResolverTests {
    // deletingLastPathComponent() on "/" yields "/.." forever; before the
    // explicit root check this walked the app into an infinite startup loop.
    @Test
    func ascendTerminatesWhenNoProjectRootExists() {
        let resolver = JournalConfigResolver()
        #expect(resolver.ascendForProjectRoot(startingAt: URL(fileURLWithPath: "/private/tmp")) == nil)
        #expect(resolver.ascendForProjectRoot(startingAt: URL(fileURLWithPath: "/")) == nil)
    }

    @Test
    func ascendFindsMarkedProjectRoot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try "".write(to: root.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        try "".write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let resolver = JournalConfigResolver()
        let found = resolver.ascendForProjectRoot(startingAt: nested)
        #expect(found?.standardizedFileURL.path == root.standardizedFileURL.path)
    }
}

@MainActor
struct TasksModelTests {
    private func makeModel() throws -> TasksModel {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = tempDir.appendingPathComponent("TASKS.md")
        return TasksModel(fileURL: fileURL)
    }

    @Test
    func createsTemplateWhenFileIsMissing() async throws {
        let model = try makeModel()
        model.prepareForDisplay()
        await model.waitForPendingLoad()

        #expect(FileManager.default.fileExists(atPath: model.fileURL.path))
        #expect(model.content.hasPrefix("# TASKS"))
        #expect(model.isDirty == false)
    }

    @Test
    func reloadsExternalChangesWhenClean() async throws {
        let model = try makeModel()
        model.prepareForDisplay()
        await model.waitForPendingLoad()

        try "# TASKS\n\n- [ ] from agent\n".write(to: model.fileURL, atomically: true, encoding: .utf8)
        model.prepareForDisplay()
        await model.waitForPendingLoad()

        #expect(model.content.contains("from agent"))
    }

    @Test
    func keepsDirtyEditsOnDisplay() async throws {
        let model = try makeModel()
        model.prepareForDisplay()
        await model.waitForPendingLoad()

        model.content += "\n- [ ] my unsaved edit"
        try "# TASKS\nexternal\n".write(to: model.fileURL, atomically: true, encoding: .utf8)
        model.prepareForDisplay()
        await model.waitForPendingLoad()

        #expect(model.content.contains("my unsaved edit"))
    }

    @Test
    func flushWritesOnlyWhenDirty() async throws {
        let model = try makeModel()
        model.prepareForDisplay()
        await model.waitForPendingLoad()

        // Clean editor must never overwrite newer external content.
        try "external update\n".write(to: model.fileURL, atomically: true, encoding: .utf8)
        model.flush()
        #expect(try String(contentsOf: model.fileURL, encoding: .utf8) == "external update\n")

        model.content = "edited in panel\n"
        model.flush()
        #expect(try String(contentsOf: model.fileURL, encoding: .utf8) == "edited in panel\n")
        #expect(model.isDirty == false)
    }
}
