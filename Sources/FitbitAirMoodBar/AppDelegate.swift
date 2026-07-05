import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState.shared
    private var statusItemController: StatusItemController?
    private var mainWindowController: MainWindowController?
    private var reminderPanelController: ReminderPanelController?
    private var hotKeyCenter: HotKeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenuBuilder.install()
        appState.bindPresentationHandlers(
            openMainWindow: { [weak self] in
                self?.openMainWindow()
            },
            toggleQuickCheckIn: { [weak self] in
                self?.toggleQuickCheckIn()
            },
            presentReminderPanel: { [weak self] in
                self?.presentReminderPanel()
            },
            dismissReminderPanel: { [weak self] in
                self?.dismissReminderPanel()
            }
        )

        statusItemController = StatusItemController(
            statusSummaryProvider: { [weak self] in
                self?.appState.latestStatusItemSummary()
            },
            onPrimaryActivate: { [weak self] in
                self?.appState.toggleQuickCheckIn()
            },
            onOpenWindow: { [weak self] in
                self?.appState.openMainWindow()
            },
            onOpenTodayJournal: { [weak self] in
                self?.appState.openTodayJournal()
            },
            onWeeklyInsights: { [weak self] in
                self?.appState.appendWeeklyInsightsAndOpenTodayJournal()
            },
            onOpenDatabase: { [weak self] in
                self?.appState.openDatabaseFolder()
            },
            onSyncFitbit: { [weak self] in
                self?.appState.syncFitbitNow()
            },
            onTriggerReminder: { [weak self] in
                self?.appState.triggerReminderNow()
            },
            onQuit: { [weak self] in
                self?.appState.quitApplication()
            }
        )
        appState.checkInsDidChange = { [weak self] in
            self?.statusItemController?.refresh()
        }
        hotKeyCenter = HotKeyCenter { [weak self] in
            self?.appState.toggleQuickCheckIn()
        }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState.openMainWindow()
        return false
    }

    private func openMainWindow() {
        dismissReminderPanel()
        let controller = ensureMainWindowController()
        controller.normalizeWindowLevel()
        controller.showWindowAndActivate()
    }

    private func toggleQuickCheckIn() {
        if let mainWindowController, mainWindowController.isVisible {
            mainWindowController.showWindowAndActivate()
            return
        }

        appState.clearTransientCheckInMessages()
        ensureReminderPanelController().togglePanel()
    }

    private func presentReminderPanel() {
        if let mainWindowController, mainWindowController.isVisible {
            mainWindowController.showWindowAndActivate()
            return
        }

        appState.clearTransientCheckInMessages()
        ensureReminderPanelController().showPanel()
    }

    private func dismissReminderPanel() {
        reminderPanelController?.hidePanel()
    }

    private func ensureMainWindowController() -> MainWindowController {
        if let mainWindowController {
            return mainWindowController
        }

        let controller = MainWindowController(appState: appState)
        mainWindowController = controller
        return controller
    }

    private func ensureReminderPanelController() -> ReminderPanelController {
        if let reminderPanelController {
            return reminderPanelController
        }

        let controller = ReminderPanelController(appState: appState)
        reminderPanelController = controller
        return controller
    }
}
