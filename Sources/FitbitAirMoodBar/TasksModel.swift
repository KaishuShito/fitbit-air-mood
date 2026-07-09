import Foundation

// Editing model for the shared TASKS.md. The file is the source of truth and
// other agents edit it concurrently, so the rules are: reload from disk on
// every display while the editor is clean, and only ever write when the
// editor holds unsaved changes. No merging.
@MainActor
final class TasksModel: ObservableObject {
    struct FooterMessage: Equatable {
        let text: String
        let isError: Bool
    }

    static let defaultFileURL = URL(fileURLWithPath: "/Users/kai/Documents/Obsidian/TASKS.md")

    static let template = """
    # TASKS

    次の予定:

    ## いま決めること

    ## 今日

    ## 待ち（人）
    """

    @Published var content: String = ""
    @Published private(set) var footerMessage: FooterMessage?

    let fileURL: URL

    private var loadedContent: String = ""
    private var autosaveTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private(set) var loadTask: Task<Void, Never>?
    private let now: () -> Date

    private static let autosaveDelay: Duration = .milliseconds(500)
    private static let feedbackDuration: Duration = .seconds(2)

    init(fileURL: URL = TasksModel.defaultFileURL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
    }

    var isDirty: Bool {
        content != loadedContent
    }

    // MARK: - Lifecycle

    func prepareForDisplay() {
        clearFeedback()
        startLoad(feedbackOnSuccess: nil)
    }

    func flush() {
        autosaveTask?.cancel()
        autosaveTask = nil
        guard isDirty else { return }
        writeToDisk()
    }

    // MARK: - Actions

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            guard let self, self.isDirty else { return }
            self.writeToDisk()
        }
    }

    func saveNow() {
        autosaveTask?.cancel()
        autosaveTask = nil
        if isDirty {
            if writeToDisk() {
                showFeedback(FooterMessage(text: "Saved \(Self.timeString(now()))", isError: false))
            }
        } else {
            showFeedback(FooterMessage(text: "No changes", isError: false))
        }
    }

    func reloadNow() {
        flush()
        startLoad(feedbackOnSuccess: "Reloaded")
    }

    // Awaitable by tests and callers that need the load settled.
    func waitForPendingLoad() async {
        await loadTask?.value
    }

    // MARK: - Disk

    // Reads happen off the main thread: the first access after a rebuild can
    // block for many seconds behind the Documents-folder TCC check, and a
    // synchronous read would freeze the whole app (hotkeys included).
    private func startLoad(feedbackOnSuccess: String?) {
        // A dirty editor means a flush failed earlier; keep the edits on
        // screen instead of silently replacing them with the disk copy.
        guard !isDirty else { return }
        loadTask?.cancel()
        let url = fileURL
        let template = Self.template
        loadTask = Task { [weak self] in
            let result: Result<String, Error> = await Task.detached {
                do {
                    let fileManager = FileManager.default
                    if !fileManager.fileExists(atPath: url.path) {
                        try fileManager.createDirectory(
                            at: url.deletingLastPathComponent(),
                            withIntermediateDirectories: true
                        )
                        try (template + "\n").write(to: url, atomically: true, encoding: .utf8)
                    }
                    return .success(try String(contentsOf: url, encoding: .utf8))
                } catch {
                    return .failure(error)
                }
            }.value

            guard let self, !Task.isCancelled else { return }
            switch result {
            case .success(let text):
                // The user may have started typing while the read was in
                // flight; their edits win.
                guard !self.isDirty else { return }
                self.loadedContent = text
                self.content = text
                if let feedbackOnSuccess {
                    self.showFeedback(FooterMessage(
                        text: "\(feedbackOnSuccess) \(Self.timeString(self.now()))",
                        isError: false
                    ))
                }
            case .failure(let error):
                self.showFeedback(FooterMessage(text: "Load failed: \(error.localizedDescription)", isError: true))
            }
        }
    }

    @discardableResult
    private func writeToDisk() -> Bool {
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            loadedContent = content
            return true
        } catch {
            showFeedback(FooterMessage(text: "Save failed: \(error.localizedDescription)", isError: true))
            return false
        }
    }

    // MARK: - Feedback

    private func showFeedback(_ message: FooterMessage) {
        footerMessage = message
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackDuration)
            guard !Task.isCancelled else { return }
            self?.footerMessage = nil
        }
    }

    private func clearFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        footerMessage = nil
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
