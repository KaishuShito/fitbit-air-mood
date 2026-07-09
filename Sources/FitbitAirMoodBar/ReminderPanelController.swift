import AppKit
import SwiftUI

private final class MoodReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ReminderPanelController: NSWindowController, NSWindowDelegate {
    private static let basePanelHeight: CGFloat = 420
    private static let fallbackPanelWidth: CGFloat = 360
    private let appState: AppState
    private let hosting: NSHostingController<CheckInView>
    private let panel: MoodReminderPanel
    private var keyMonitor: Any?

    init(appState: AppState) {
        self.appState = appState
        self.hosting = NSHostingController(
            rootView: CheckInView(
                appState: appState,
                mode: .panel,
                onDismiss: {
                    appState.dismissReminderPanel()
                }
            )
        )
        panel = MoodReminderPanel(
            contentRect: NSRect(origin: .zero, size: Self.fallbackPanelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Quick Check-In"
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = hosting
        super.init(window: panel)
        panel.delegate = self
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func showPanel() {
        appState.preparePanelCheckIn()
        positionPanel()
        let targetFrame = panel.frame
        var startFrame = targetFrame
        startFrame.origin.y += targetFrame.height * 0.85
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The always-visible notes NSTextView is the first key view, so AppKit
        // focuses it when the panel becomes key; digits must go to the Mood row.
        panel.makeFirstResponder(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
    }

    func hidePanel() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func positionPanel() {
        let placement = NotchPanelGeometry.placement(
            baseHeight: Self.basePanelHeight,
            fallbackWidth: Self.fallbackPanelWidth
        )
        hosting.rootView = CheckInView(
            appState: appState,
            mode: .panel,
            onDismiss: { [weak appState] in
                appState?.dismissReminderPanel()
            },
            panelTopInset: placement.topInset,
            panelWidth: placement.width
        )
        panel.setFrame(placement.frame, display: false)
    }

    private static var fallbackPanelSize: NSSize {
        NSSize(width: fallbackPanelWidth, height: basePanelHeight)
    }

    nonisolated func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor in
            installKeyMonitor()
        }
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            removeKeyMonitor()
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
        guard panel.isVisible, panel.isKeyWindow, let input = panelKeyInput(for: event) else {
            return event
        }

        let actions = PanelKeyRouter.actions(
            for: input,
            activeRow: appState.panelActiveRow,
            notesFocused: isNotesFocused
        )
        guard !actions.isEmpty else { return event }

        apply(actions)
        return nil
    }

    private var isNotesFocused: Bool {
        panel.firstResponder is NSTextView
    }

    private func panelKeyInput(for event: NSEvent) -> PanelKeyInput? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased()

        if flags == .command, characters == "\r" {
            return .commandReturn
        }

        guard flags.subtracting(.shift).isEmpty else {
            return nil
        }

        switch event.keyCode {
        case 48:
            return .tab
        case 123:
            return .left
        case 124:
            return .right
        case 125:
            return .down
        case 126:
            return .up
        case 53:
            return .escape
        default:
            break
        }

        switch characters {
        case "1", "2", "3", "4", "5":
            return .digit(Int(characters ?? "") ?? 0)
        case "n":
            return .note
        case "\r":
            return .return
        case "\u{1b}":
            return .escape
        default:
            return nil
        }
    }

    private func apply(_ actions: [PanelKeyAction]) {
        for action in actions {
            switch action {
            case .setValue(let row, let value):
                appState.setPanelValue(row: row, value: value)
            case .changeValue(let row, let delta):
                appState.changePanelValue(row: row, delta: delta)
            case .setActiveRow(let row):
                appState.panelActiveRow = row
            case .focusNotes:
                focusNotesAfterLayout()
            case .save, .saveFromNotes:
                appState.saveCheckIn(fromPanel: true)
            case .leaveNotes:
                panel.makeFirstResponder(nil)
            case .dismiss:
                appState.dismissReminderPanel()
            }
        }
    }

    private func focusNotesAfterLayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .fitbitAirMoodBarFocusNotes, object: nil)
        }
    }
}
