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
    private static let notchWingPadding: CGFloat = 220
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
        showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        let screen = screenWithCameraHousing() ?? screenForCurrentPointer() ?? NSScreen.main
        let panelSize = configurePanel(for: screen)
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let centerX = cameraHousingCenterX(on: screen) ?? visibleFrame.midX
        let usesCameraHousing = panelTopInset(on: screen) > 0
        let topY = usesCameraHousing ? (screen?.frame.maxY ?? visibleFrame.maxY) : visibleFrame.maxY
        let origin = NSPoint(
            x: clamped(centerX - (panelSize.width / 2), min: visibleFrame.minX + 12, max: visibleFrame.maxX - panelSize.width - 12),
            y: usesCameraHousing ? topY - panelSize.height : topY - panelSize.height - 10
        )
        panel.setFrame(NSRect(origin: origin, size: panelSize), display: false)
    }

    private static var fallbackPanelSize: NSSize {
        NSSize(width: fallbackPanelWidth, height: basePanelHeight)
    }

    private func configurePanel(for screen: NSScreen?) -> NSSize {
        let topInset = panelTopInset(on: screen)
        let width = panelWidth(on: screen)
        let size = NSSize(width: width, height: Self.basePanelHeight + topInset)
        hosting.rootView = CheckInView(
            appState: appState,
            mode: .panel,
            onDismiss: { [weak appState] in
                appState?.dismissReminderPanel()
            },
            panelTopInset: topInset,
            panelWidth: width
        )
        return size
    }

    private func panelTopInset(on screen: NSScreen?) -> CGFloat {
        guard
            let screen,
            screen.safeAreaInsets.top > 0,
            cameraHousingCenterX(on: screen) != nil
        else {
            return 0
        }

        return screen.safeAreaInsets.top
    }

    private func panelWidth(on screen: NSScreen?) -> CGFloat {
        guard
            let screen,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            !left.isEmpty,
            !right.isEmpty,
            left.maxX < right.minX
        else {
            return Self.fallbackPanelWidth
        }

        return max(Self.fallbackPanelWidth, (right.minX - left.maxX) + Self.notchWingPadding)
    }

    private func screenWithCameraHousing() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard screen.safeAreaInsets.top > 0 else { return false }
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
                return false
            }
            return !left.isEmpty && !right.isEmpty && left.maxX < right.minX
        }
    }

    private func cameraHousingCenterX(on screen: NSScreen?) -> CGFloat? {
        guard
            let screen,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            !left.isEmpty,
            !right.isEmpty,
            left.maxX < right.minX
        else {
            return nil
        }

        return (left.maxX + right.minX) / 2
    }

    private func cameraHousingBottomY(on screen: NSScreen?) -> CGFloat? {
        guard
            let screen,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            !left.isEmpty,
            !right.isEmpty
        else {
            return nil
        }

        return min(left.minY, right.minY)
    }

    private func screenForCurrentPointer() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(location)
        }
    }

    private func clamped(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.max(lowerBound, Swift.min(value, upperBound))
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
            case .revealNotes:
                appState.isPanelNotesVisible = true
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
