import AppKit
import SwiftUI

extension Notification.Name {
    static let fitbitAirMoodBarFocusNotes = Notification.Name("fitbitAirMoodBarFocusNotes")
}

struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    let isDarkHUD: Bool
    let onFocusChange: ((Bool) -> Void)?

    init(text: Binding<String>, isDarkHUD: Bool = false, onFocusChange: ((Bool) -> Void)? = nil) {
        self._text = text
        self.isDarkHUD = isDarkHUD
        self.onFocusChange = onFocusChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let textView = CommandFriendlyTextView()
        textView.onFocusChange = onFocusChange
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Notes")

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.installFocusObserver()
        configure(scrollView, textView: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }

        context.coordinator.text = $text
        context.coordinator.textView = textView
        configure(scrollView, textView: textView)
    }

    private func configure(_ scrollView: NSScrollView, textView: NSTextView) {
        if isDarkHUD {
            let darkAppearance = NSAppearance(named: .darkAqua)
            scrollView.appearance = darkAppearance
            textView.appearance = darkAppearance
            textView.textColor = .white
            textView.insertionPointColor = .white
        } else {
            scrollView.appearance = nil
            textView.appearance = nil
            textView.textColor = .labelColor
            textView.insertionPointColor = .labelColor
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: NSTextView?
        private var isObservingFocus = false

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        deinit {
            if isObservingFocus {
                NotificationCenter.default.removeObserver(self)
            }
        }

        func installFocusObserver() {
            guard !isObservingFocus else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusNotes),
                name: .fitbitAirMoodBarFocusNotes,
                object: nil
            )
            isObservingFocus = true
        }

        func focusTextView() {
            guard let textView else { return }
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }

        @objc private func handleFocusNotes() {
            focusTextView()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

private final class CommandFriendlyTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            onFocusChange?(true)
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted {
            onFocusChange?(false)
        }
        return accepted
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            if flags.contains(.option), flags.contains(.shift) {
                pasteAsPlainText(nil)
            } else {
                paste(nil)
            }
            return true
        case "x":
            cut(nil)
            return true
        case "z":
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
