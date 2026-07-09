import AppKit
import SwiftUI

extension Notification.Name {
    static let fitbitAirMoodBarFocusTasks = Notification.Name("fitbitAirMoodBarFocusTasks")
}

// Applies the light markdown decoration to the plain-text editor: headings,
// checkboxes, bullets, separators. The raw characters stay untouched; the
// whole document is restyled after each edit, which is fine at TASKS.md size.
enum TasksMarkdownStyler {
    static let bodyFontSize: CGFloat = 13

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.5
        return [
            .font: NSFont.systemFont(ofSize: bodyFontSize),
            .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            .paragraphStyle: paragraph,
        ]
    }

    static func apply(to textStorage: NSTextStorage) {
        let ns = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        textStorage.beginEditing()
        textStorage.setAttributes(bodyAttributes, range: fullRange)

        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            style(line: line, at: lineRange, in: textStorage)
        }

        textStorage.endEditing()
    }

    private static func style(line: String, at range: NSRange, in textStorage: NSTextStorage) {
        switch TaskLineClassifier.classify(line) {
        case .heading(let level):
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2.5
            paragraph.paragraphSpacingBefore = range.location == 0 ? 0 : 10
            paragraph.paragraphSpacing = 3
            textStorage.addAttributes([
                .font: NSFont.systemFont(ofSize: headingFontSize(level: level), weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph,
            ], range: range)
            let hashLength = min(level + 1, range.length)
            textStorage.addAttribute(
                .foregroundColor,
                value: NSColor.white.withAlphaComponent(0.32),
                range: NSRange(location: range.location, length: hashLength)
            )
        case .checkbox(let checked, let markerLength):
            let safeMarkerLength = min(markerLength, range.length)
            textStorage.addAttribute(
                .foregroundColor,
                value: NSColor.white.withAlphaComponent(checked ? 0.32 : 0.5),
                range: NSRange(location: range.location, length: safeMarkerLength)
            )
            if checked, range.length > safeMarkerLength {
                let contentRange = NSRange(
                    location: range.location + safeMarkerLength,
                    length: range.length - safeMarkerLength
                )
                textStorage.addAttributes([
                    .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: NSColor.white.withAlphaComponent(0.3),
                ], range: contentRange)
            }
        case .bullet(let markerLength):
            textStorage.addAttribute(
                .foregroundColor,
                value: NSColor.white.withAlphaComponent(0.5),
                range: NSRange(location: range.location, length: min(markerLength, range.length))
            )
        case .separator:
            textStorage.addAttribute(
                .foregroundColor,
                value: NSColor.white.withAlphaComponent(0.28),
                range: range
            )
        case .body:
            break
        }
    }

    private static func headingFontSize(level: Int) -> CGFloat {
        switch level {
        case 1: 16
        case 2: 14
        default: 13
        }
    }
}

// The Tasks editor view: ⌘L toggles the checkbox on the caret line and the
// "[ ]" / "[x]" brackets toggle on a direct click (Notion-style), in addition
// to the clipboard/undo keys CommandFriendlyTextView already covers. Only the
// bracket glyphs are a click target, so caret placement and text selection
// anywhere else in the line stay untouched.
final class TasksNSTextView: CommandFriendlyTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "l" {
            toggleCheckboxAtSelection()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func toggleCheckboxAtSelection() {
        let selection = selectedRange()
        toggleCheckbox(atCharacterIndex: selection.location, movingCaret: true)
    }

    override func mouseDown(with event: NSEvent) {
        if !hasMarkedText() {
            let point = convert(event.locationInWindow, from: nil)
            for range in checkboxBracketRanges() where bracketHitRect(for: range)?.contains(point) == true {
                toggleCheckbox(atCharacterIndex: range.location, movingCaret: false)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for range in checkboxBracketRanges() {
            if let rect = bracketHitRect(for: range) {
                addCursorRect(rect, cursor: .pointingHand)
            }
        }
    }

    private func toggleCheckbox(atCharacterIndex index: Int, movingCaret: Bool) {
        guard !hasMarkedText() else { return }
        guard let edit = TaskCheckboxToggler.edit(text: string, selectionLocation: index) else { return }
        let previousSelection = selectedRange()
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        if movingCaret {
            setSelectedRange(NSRange(location: edit.selectionLocation, length: 0))
        } else {
            // Checkbox toggles never change the line length, so the previous
            // selection stays valid; a click should not steal the caret.
            setSelectedRange(previousSelection)
        }
        window?.invalidateCursorRects(for: self)
    }

    // Character ranges of every "[ ]" / "[x]" bracket group in the document.
    private func checkboxBracketRanges() -> [NSRange] {
        let ns = string as NSString
        var ranges: [NSRange] = []
        ns.enumerateSubstrings(
            in: NSRange(location: 0, length: ns.length),
            options: [.byLines, .substringNotRequired]
        ) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange)
            if case .checkbox(_, let markerLength) = TaskLineClassifier.classify(line), markerLength >= 4 {
                ranges.append(NSRange(location: lineRange.location + markerLength - 4, length: 3))
            }
        }
        return ranges
    }

    private func bracketHitRect(for characterRange: NSRange) -> NSRect? {
        guard let layoutManager, let textContainer else { return nil }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        return rect.insetBy(dx: -3, dy: -2)
    }
}

struct TasksTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.appearance = NSAppearance(named: .darkAqua)

        let textView = TasksNSTextView()
        textView.delegate = context.coordinator
        textView.appearance = NSAppearance(named: .darkAqua)
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Tasks")
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.4),
        ]

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.installFocusObserver()
        context.coordinator.setTextAndRestyle(text)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? TasksNSTextView else { return }
        context.coordinator.text = $text
        context.coordinator.textView = textView

        if textView.string != text, !textView.hasMarkedText() {
            context.coordinator.setTextAndRestyle(text)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: TasksNSTextView?

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func installFocusObserver() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusTasks),
                name: .fitbitAirMoodBarFocusTasks,
                object: nil
            )
        }

        func setTextAndRestyle(_ newText: String) {
            guard let textView else { return }
            textView.string = newText
            restyle()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scroll(.zero)
        }

        @objc private func handleFocusTasks() {
            guard let textView else { return }
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text.wrappedValue = textView.string
            restyle()
        }

        private func restyle() {
            guard let textView, let textStorage = textView.textStorage else { return }
            // Styling during an IME composition (Japanese input) would break
            // the marked-text underline; restyle once the text is committed.
            guard !textView.hasMarkedText() else { return }
            TasksMarkdownStyler.apply(to: textStorage)
            textView.typingAttributes = TasksMarkdownStyler.bodyAttributes
            // Checkbox lines may have appeared or moved; refresh their
            // pointing-hand cursor rects.
            textView.window?.invalidateCursorRects(for: textView)
        }
    }
}
