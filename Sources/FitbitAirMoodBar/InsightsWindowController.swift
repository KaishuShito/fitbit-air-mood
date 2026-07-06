import AppKit
import SwiftUI

@MainActor
final class InsightsWindowController: NSWindowController, NSWindowDelegate {
    init(appState: AppState) {
        let hosting = NSHostingController(rootView: InsightsView(appState: appState))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 480)
        window.title = "Mood Insights"
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
        NotificationCenter.default.post(name: .fitbitAirMoodBarRefreshInsights, object: nil)
    }
}
