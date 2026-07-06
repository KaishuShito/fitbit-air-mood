import AppKit
import SwiftUI

extension Notification.Name {
    static let fitbitAirMoodBarFocusNotes = Notification.Name("fitbitAirMoodBarFocusNotes")
    static let fitbitAirMoodBarFocusQuickNote = Notification.Name("fitbitAirMoodBarFocusQuickNote")
}

struct NotesTextView: NSViewRepresentable {
    @Binding var text: String
    let isDarkHUD: Bool
    let placeholder: String?
    let fontSize: CGFloat
    let contentInset: CGFloat
    let focusNotification: Notification.Name
    let onFocusChange: ((Bool) -> Void)?

    init(
        text: Binding<String>,
        isDarkHUD: Bool = false,
        placeholder: String? = nil,
        fontSize: CGFloat = NSFont.systemFontSize,
        contentInset: CGFloat = 6,
        focusNotification: Notification.Name = .fitbitAirMoodBarFocusNotes,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self._text = text
        self.isDarkHUD = isDarkHUD
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.contentInset = contentInset
        self.focusNotification = focusNotification
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
        textView.placeholderString = placeholder
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = .systemFont(ofSize: fontSize)
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
        textView.textContainerInset = NSSize(width: contentInset, height: contentInset)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityLabel("Notes")

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.installFocusObserver(name: focusNotification)
        configure(scrollView, textView: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CommandFriendlyTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
            textView.needsDisplay = true
        }

        textView.placeholderString = placeholder
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
        private var focusNotificationName: Notification.Name?

        init(text: Binding<String>) {
            self.text = text
            super.init()
        }

        deinit {
            if focusNotificationName != nil {
                NotificationCenter.default.removeObserver(self)
            }
        }

        func installFocusObserver(name: Notification.Name) {
            guard focusNotificationName == nil else { return }
            focusNotificationName = name
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusNotes),
                name: name,
                object: nil
            )
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
            textView.needsDisplay = true
        }
    }
}

private final class CommandFriendlyTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?
    var placeholderString: String?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty, let placeholderString, !placeholderString.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
        ]
        let origin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholderString.draw(at: origin, withAttributes: attributes)
    }

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
