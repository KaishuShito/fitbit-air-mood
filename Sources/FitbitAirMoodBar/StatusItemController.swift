import AppKit

struct StatusItemSummary: Equatable {
    let recordedAt: Date
    let moodValue: Int
    let energyValue: Int
}

struct StatusItemDisplayLogic {
    static func buttonTitle(moodValue: Int) -> String? {
        MoodLevel(rawValue: moodValue)?.emoji
    }

    static func relativeTimeString(from recordedAt: Date, now: Date = Date()) -> String {
        let elapsedMinutes = max(0, Int(now.timeIntervalSince(recordedAt) / 60))
        guard elapsedMinutes >= 60 else {
            return "\(elapsedMinutes)m ago"
        }

        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60
        return "\(hours)h \(minutes)m ago"
    }

    static func menuTitle(summary: StatusItemSummary?, now: Date = Date()) -> String {
        guard let summary else {
            return "No check-in yet today"
        }

        let timeString = localTimeString(for: summary.recordedAt)
        let relativeTime = relativeTimeString(from: summary.recordedAt, now: now)
        return "Last check-in \(timeString) (\(relativeTime)) — Mood \(summary.moodValue) · Energy \(summary.energyValue)"
    }

    private static func localTimeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusSummaryItem = NSMenuItem(title: "No check-in yet today", action: nil, keyEquivalent: "")
    private let onPrimaryActivate: () -> Void
    private let onOpenWindow: () -> Void
    private let onOpenInsights: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onOpenTodayJournal: () -> Void
    private let onWeeklyInsights: () -> Void
    private let onOpenDatabase: () -> Void
    private let onSyncFitbit: () -> Void
    private let onTriggerReminder: () -> Void
    private let onQuit: () -> Void
    private let statusSummaryProvider: () -> StatusItemSummary?

    init(
        statusSummaryProvider: @escaping () -> StatusItemSummary?,
        onPrimaryActivate: @escaping () -> Void,
        onOpenWindow: @escaping () -> Void,
        onOpenInsights: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void,
        onOpenTodayJournal: @escaping () -> Void,
        onWeeklyInsights: @escaping () -> Void,
        onOpenDatabase: @escaping () -> Void,
        onSyncFitbit: @escaping () -> Void,
        onTriggerReminder: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.statusSummaryProvider = statusSummaryProvider
        self.onPrimaryActivate = onPrimaryActivate
        self.onOpenWindow = onOpenWindow
        self.onOpenInsights = onOpenInsights
        self.onCheckForUpdates = onCheckForUpdates
        self.onOpenTodayJournal = onOpenTodayJournal
        self.onWeeklyInsights = onWeeklyInsights
        self.onOpenDatabase = onOpenDatabase
        self.onSyncFitbit = onSyncFitbit
        self.onTriggerReminder = onTriggerReminder
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureMenu()
        configureStatusItem()
        refresh()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            statusItem.length = NSStatusItem.squareLength
            applyFallbackImage(to: button)
            button.toolTip = "Fitbit Air Mood Check-In"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(handleActivate(_:))
        }
    }

    private func configureMenu() {
        menu.delegate = self
        statusSummaryItem.isEnabled = false
        menu.addItem(statusSummaryItem)
        menu.addItem(.separator())

        let openWindowItem = NSMenuItem(title: "Open Full Window", action: #selector(openWindow), keyEquivalent: "o")
        openWindowItem.keyEquivalentModifierMask = [.command]
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        let quickCheckInItem = NSMenuItem(title: "Check In Now", action: #selector(triggerReminder), keyEquivalent: "m")
        quickCheckInItem.keyEquivalentModifierMask = [.control, .option]
        quickCheckInItem.target = self
        menu.addItem(quickCheckInItem)

        let insightsItem = NSMenuItem(title: "Insights…", action: #selector(openInsights), keyEquivalent: "i")
        insightsItem.keyEquivalentModifierMask = [.command]
        insightsItem.target = self
        menu.addItem(insightsItem)

        let checkForUpdatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())

        let syncFitbitItem = NSMenuItem(title: "Sync Fitbit Now", action: #selector(syncFitbit), keyEquivalent: "")
        syncFitbitItem.target = self
        menu.addItem(syncFitbitItem)

        let openJournalItem = NSMenuItem(title: "Open Today's Journal", action: #selector(openTodayJournal), keyEquivalent: "")
        openJournalItem.target = self
        menu.addItem(openJournalItem)

        let weeklyInsightsItem = NSMenuItem(title: "Weekly Insights", action: #selector(weeklyInsights), keyEquivalent: "")
        weeklyInsightsItem.target = self
        menu.addItem(weeklyInsightsItem)

        let showDatabaseItem = NSMenuItem(title: "Show Database", action: #selector(openDatabase), keyEquivalent: "")
        showDatabaseItem.target = self
        menu.addItem(showDatabaseItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit FitbitAirMoodBar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func handleActivate(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            onPrimaryActivate()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onPrimaryActivate()
        }
    }

    func refresh() {
        let summary = statusSummaryProvider()
        statusSummaryItem.title = StatusItemDisplayLogic.menuTitle(summary: summary)

        guard let button = statusItem.button else { return }
        if let moodValue = summary?.moodValue,
           let title = StatusItemDisplayLogic.buttonTitle(moodValue: moodValue) {
            button.image = nil
            button.title = title
        } else {
            applyFallbackImage(to: button)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func applyFallbackImage(to button: NSStatusBarButton) {
        if let image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "Fitbit Air Mood") {
            image.isTemplate = true
            button.title = ""
            button.image = image
        } else {
            button.image = nil
            button.title = "M"
        }
    }

    @objc private func openWindow() {
        onOpenWindow()
    }

    @objc private func openInsights() {
        onOpenInsights()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func openTodayJournal() {
        onOpenTodayJournal()
    }

    @objc private func weeklyInsights() {
        onWeeklyInsights()
    }

    @objc private func openDatabase() {
        onOpenDatabase()
    }

    @objc private func syncFitbit() {
        onSyncFitbit()
    }

    @objc private func triggerReminder() {
        onTriggerReminder()
    }

    @objc private func quit() {
        onQuit()
    }
}
