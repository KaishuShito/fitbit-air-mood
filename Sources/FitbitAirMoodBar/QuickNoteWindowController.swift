import AppKit
import SwiftUI

private final class QuickNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class QuickNoteWindowController: NSWindowController, NSWindowDelegate {
    private let model: QuickNoteModel
    private let panel: QuickNotePanel
    private var keyMonitor: Any?

    init(model: QuickNoteModel) {
        self.model = model
        let hosting = NSHostingController(rootView: QuickNoteView(model: model))
        panel = QuickNotePanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.title = "Quick Note"
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.hidesOnDeactivate = false
        panel.minSize = NSSize(width: 360, height: 280)
        panel.contentViewController = hosting
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.center()
        super.init(window: panel)
        panel.delegate = self
        panel.setFrameAutosaveName("FitbitAirMoodBarQuickNoteWindow")
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.requestCloseWindow = { [weak self] in
            self?.hide()
        }
        model.prepareForDisplay()
        showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitor()
        focusEditor()
    }

    func hide() {
        model.flush()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func flushPendingEdits() {
        model.flush()
    }

    private func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .fitbitAirMoodBarFocusQuickNote, object: nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.flush()
        removeKeyMonitor()
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            model.flush()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Scope strictly to this window so the check-in panel's own monitor and
        // any other window keep their key handling untouched.
        guard panel.isVisible, panel.isKeyWindow else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()
        let overlayOpen = model.isBrowsing || model.isShowingActions

        if flags == .command {
            switch characters {
            case "\r":
                model.saveToJournal()
                return nil
            case "n":
                model.newNote()
                return nil
            case "p":
                model.toggleBrowsing()
                return nil
            case "k":
                model.toggleActions()
                return nil
            default:
                break
            }

            // ⌘⌫ deletes the keyboard-selected note in the browse overlay.
            if event.keyCode == 51, model.isBrowsing {
                model.deleteSelectedNote()
                return nil
            }
            return event
        }

        guard flags.subtracting(.shift).isEmpty else { return event }

        switch event.keyCode {
        case 53: // esc — close the open overlay first, otherwise the window.
            if model.isShowingActions {
                model.toggleActions()
            } else if model.isBrowsing {
                model.toggleBrowsing()
            } else {
                hide()
            }
            return nil
        case 125: // down arrow
            if overlayOpen {
                model.moveSelection(by: 1)
                return nil
            }
            return event
        case 126: // up arrow
            if overlayOpen {
                model.moveSelection(by: -1)
                return nil
            }
            return event
        case 36: // return — activate the selected row while an overlay is open.
            if overlayOpen {
                model.activateSelection()
                return nil
            }
            return event
        default:
            return event
        }
    }
}
