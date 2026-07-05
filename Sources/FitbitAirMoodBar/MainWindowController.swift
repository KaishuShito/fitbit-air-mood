import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let hosting = NSHostingController(
            rootView: ScrollView {
                CheckInView(
                    appState: appState,
                    mode: .window
                )
            }
            .frame(width: 420, height: 720)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 420, height: 560)
        window.title = "Fitbit Air Mood"
        window.center()
        window.contentViewController = hosting
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        window.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func showWindowAndActivate() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusNotes()
    }

    func showReminderWindow() {
        showWindowAndActivate()
        window?.level = .floating
    }

    func normalizeWindowLevel() {
        window?.level = .normal
    }

    func closeWindow() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        normalizeWindowLevel()
    }

    private func focusNotes() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .fitbitAirMoodBarFocusNotes, object: nil)
        }
    }
}
