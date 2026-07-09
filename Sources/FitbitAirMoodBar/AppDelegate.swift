import AppKit
import Sparkle
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState.shared
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var statusItemController: StatusItemController?
    private var mainWindowController: MainWindowController?
    private var insightsWindowController: InsightsWindowController?
    private var reminderPanelController: ReminderPanelController?
    private var quickNoteWindowController: QuickNoteWindowController?
    private let tasksModel = TasksModel()
    private var tasksPanelController: TasksPanelController?
    private var hotKeyCenter: HotKeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenuBuilder.install()
        appState.bindPresentationHandlers(
            openMainWindow: { [weak self] in
                self?.openMainWindow()
            },
            openInsightsWindow: { [weak self] in
                self?.openInsightsWindow()
            },
            toggleQuickCheckIn: { [weak self] in
                self?.toggleQuickCheckIn()
            },
            toggleQuickNote: { [weak self] in
                self?.toggleQuickNote()
            },
            toggleTasks: { [weak self] in
                self?.toggleTasks()
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
            onQuickNote: { [weak self] in
                self?.appState.toggleQuickNote()
            },
            onOpenTasks: { [weak self] in
                self?.appState.toggleTasks()
            },
            onOpenWindow: { [weak self] in
                self?.appState.openMainWindow()
            },
            onOpenInsights: { [weak self] in
                self?.appState.openInsightsWindow()
            },
            onCheckForUpdates: { [weak self] in
                self?.checkForUpdates()
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
        hotKeyCenter = HotKeyCenter(registrations: [
            HotKeyCenter.Registration(keyCode: 46, modifiers: HotKeyCenter.controlOption) { [weak self] in
                self?.appState.toggleQuickCheckIn()
            },
            HotKeyCenter.Registration(keyCode: 45, modifiers: HotKeyCenter.controlOption) { [weak self] in
                self?.appState.toggleQuickNote()
            },
            HotKeyCenter.Registration(keyCode: 17, modifiers: HotKeyCenter.controlOption) { [weak self] in
                self?.appState.toggleTasks()
            },
        ])
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        quickNoteWindowController?.flushPendingEdits()
        tasksModel.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState.openMainWindow()
        return false
    }

    // fitbitairmood://tasks|check-in|note — the same toggles the global
    // hotkeys drive, for Raycast/scripting/agent-driven verification.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            os_log(.info, "URL open: %{public}@", url.absoluteString)
            switch url.host ?? url.lastPathComponent {
            case "tasks":
                appState.toggleTasks()
            case "check-in":
                appState.toggleQuickCheckIn()
            case "note":
                appState.toggleQuickNote()
            case "sync":
                appState.syncFitbitNow()
            default:
                break
            }
        }
    }

    private func openMainWindow() {
        dismissReminderPanel()
        let controller = ensureMainWindowController()
        controller.normalizeWindowLevel()
        controller.showWindowAndActivate()
    }

    private func openInsightsWindow() {
        ensureInsightsWindowController().showWindowAndActivate()
    }

    private func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func toggleQuickCheckIn() {
        if let mainWindowController, mainWindowController.isVisible {
            mainWindowController.showWindowAndActivate()
            return
        }

        appState.clearTransientCheckInMessages()
        ensureReminderPanelController().togglePanel()
    }

    private func toggleQuickNote() {
        ensureQuickNoteWindowController().toggle()
    }

    private func toggleTasks() {
        ensureTasksPanelController().togglePanel()
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

    private func ensureInsightsWindowController() -> InsightsWindowController {
        if let insightsWindowController {
            return insightsWindowController
        }

        let controller = InsightsWindowController(appState: appState)
        insightsWindowController = controller
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

    private func ensureQuickNoteWindowController() -> QuickNoteWindowController {
        if let quickNoteWindowController {
            return quickNoteWindowController
        }

        let controller = QuickNoteWindowController(model: appState.quickNoteModel)
        quickNoteWindowController = controller
        return controller
    }

    private func ensureTasksPanelController() -> TasksPanelController {
        if let tasksPanelController {
            return tasksPanelController
        }

        let controller = TasksPanelController(model: tasksModel)
        tasksPanelController = controller
        return controller
    }
}
