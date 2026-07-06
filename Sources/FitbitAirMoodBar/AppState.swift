import AppKit
import Foundation
import ServiceManagement
@preconcurrency import UserNotifications

@MainActor
final class AppState: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = AppState()

    @Published var launchAtLoginEnabled = false
    @Published var launchAtLoginStatusMessage: String?
    @Published var quietHourlyReminders: Bool {
        didSet {
            guard quietHourlyReminders != oldValue else { return }
            UserDefaults.standard.set(quietHourlyReminders, forKey: Self.quietHourlyRemindersKey)
            rescheduleReminder()
        }
    }
    @Published var reminderEnabled: Bool {
        didSet {
            guard reminderEnabled != oldValue else { return }
            UserDefaults.standard.set(reminderEnabled, forKey: Self.reminderEnabledKey)
            if reminderEnabled {
                ensureNotificationAuthorization()
            }
            rescheduleReminder()
        }
    }
    @Published var draft = MoodDraft()
    @Published var journalDirectoryDisplay = "Detecting..."
    @Published var databasePathDisplay = ""
    @Published var saveMessage: String?
    @Published var errorMessage: String?
    @Published var notificationStatusMessage: String?
    @Published var fitbitSyncMessage: String?
    @Published var isSaving = false
    @Published var isSyncingFitbit = false
    @Published var panelActiveRow: PanelActiveRow = .mood
    @Published var isPanelNotesFocused = false

    private static let quietHourlyRemindersKey = "quietHourlyReminders"
    private static let reminderEnabledKey = "hourlyReminderEnabled"
    private static let lastInsightsISOWeekKey = "lastInsightsISOWeek"
    private nonisolated static let lastCheckInAtKey = "lastCheckInAt"
    private nonisolated static let hourlyReminderNotificationIdentifier = "mood-checkin-hourly"
    private static let manualReminderNotificationPrefix = "mood-checkin-manual-"
    private let notificationCenter = UNUserNotificationCenter.current()
    private let loginService = SMAppService.mainApp
    private let resolver = JournalConfigResolver()
    private var resolution: JournalResolution
    private let journalWriter = JournalWriter()
    private let fitbitRunner = FitbitCLIRunner()
    private let database: SQLiteStore
    private var reminderTimer: Timer?
    private var lastReminderBucket: String?
    private var isSyncingLaunchAtLogin = false
    private var openMainWindowHandler: (() -> Void)?
    private var openInsightsWindowHandler: (() -> Void)?
    private var toggleQuickCheckInHandler: (() -> Void)?
    private var toggleQuickNoteHandler: (() -> Void)?
    private var presentReminderPanelHandler: (() -> Void)?
    private var dismissReminderPanelHandler: (() -> Void)?
    var checkInsDidChange: (() -> Void)?

    lazy var quickNoteModel: QuickNoteModel = QuickNoteModel(
        store: database,
        journalWriter: journalWriter,
        journalDirectoryProvider: { [weak self] in self?.resolution.journalDirectory }
    )

    override init() {
        quietHourlyReminders = UserDefaults.standard.object(forKey: Self.quietHourlyRemindersKey) as? Bool ?? false
        reminderEnabled = UserDefaults.standard.object(forKey: Self.reminderEnabledKey) as? Bool ?? true
        resolution = resolver.resolve()
        journalDirectoryDisplay = resolution.journalDirectory?.path ?? "Not configured"
        databasePathDisplay = resolution.databaseURL.path
        database = try! SQLiteStore(databaseURL: resolution.databaseURL)
        super.init()
        notificationCenter.delegate = self
        if reminderEnabled {
            ensureNotificationAuthorization()
        }
        refreshLaunchAtLoginState()
        rescheduleReminder()
    }

    func saveCheckIn(fromPanel: Bool = false) {
        guard let journalDirectory = resolution.journalDirectory else {
            errorMessage = "Journal directory is not configured. Choose a folder first."
            saveMessage = nil
            return
        }

        isSaving = true
        errorMessage = nil
        saveMessage = nil

        let checkIn = MoodCheckIn(
            mood: draft.mood,
            energy: draft.energy,
            notes: draft.notes
        )

        let savedAt = Date()
        var shouldAutoSyncFitbit = false
        var didSaveCheckIn = false

        do {
            let fitbitSnapshotLink = try database.currentFitbitSnapshotLink(for: checkIn, now: savedAt)
            shouldAutoSyncFitbit = FitbitSnapshotFreshness.shouldAutoSync(
                snapshotAgeMinutes: fitbitSnapshotLink?.ageMinutes
            )
            let journalFile = try journalWriter.append(checkIn: checkIn, to: journalDirectory)
            try database.insert(checkIn: checkIn, journalFileURL: journalFile, fitbitSnapshotLink: fitbitSnapshotLink)
            draft.reset()
            saveMessage = fromPanel ? "✓ Saved \(Self.localTimeString(for: checkIn.recordedAt))" : "Saved \(checkIn.localTimestampString)"
            errorMessage = nil
            journalDirectoryDisplay = journalDirectory.path
            didSaveCheckIn = true
            UserDefaults.standard.set(checkIn.recordedAt.timeIntervalSince1970, forKey: Self.lastCheckInAtKey)
            checkInsDidChange?()
            if fromPanel {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.dismissReminderPanel()
                }
            } else {
                dismissReminderPanel()
            }
        } catch {
            errorMessage = error.localizedDescription
            saveMessage = nil
        }

        isSaving = false

        if didSaveCheckIn {
            Task { @MainActor in
                autoAppendWeeklyInsightsIfNeeded(after: checkIn)
            }
        }

        if didSaveCheckIn && shouldAutoSyncFitbit {
            syncFitbit(trigger: .autoCheckIn)
        }
    }

    func syncFitbitNow() {
        syncFitbit(trigger: .manual)
    }

    private enum FitbitSyncTrigger {
        case manual
        case autoCheckIn
    }

    private func syncFitbit(trigger: FitbitSyncTrigger) {
        guard !isSyncingFitbit else { return }

        isSyncingFitbit = true
        fitbitSyncMessage = trigger == .autoCheckIn ? "Syncing Fitbit after check-in..." : "Syncing Fitbit..."

        Task {
            do {
                let snapshot = try await fitbitRunner.fetchTodayJSON(projectRoot: resolution.projectRoot)
                try database.upsertFitbitSnapshot(snapshot)
                let syncedAt = Self.localTimeString(for: snapshot.recordedAt)
                switch trigger {
                case .manual:
                    fitbitSyncMessage = "Fitbit synced \(syncedAt) - \(Self.byteCountString(snapshot.payloadBytes))"
                case .autoCheckIn:
                    fitbitSyncMessage = "Auto-synced after check-in \(syncedAt) - \(Self.byteCountString(snapshot.payloadBytes))"
                }
            } catch {
                fitbitSyncMessage = "Fitbit sync failed: \(error.localizedDescription)"
            }

            isSyncingFitbit = false
        }
    }

    func chooseJournalDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Journal Folder"
        panel.message = "Choose the same daily journal folder used by fitbit-air-cli."

        if let current = resolution.journalDirectory {
            panel.directoryURL = current
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        resolver.storeOverride(url)
        refreshResolution()
    }

    func resetJournalDirectoryToDetectedDefault() {
        resolver.clearOverride()
        refreshResolution()
    }

    func openTodayJournal() {
        guard let journalDirectory = resolution.journalDirectory else {
            errorMessage = "No journal directory is configured yet."
            saveMessage = nil
            return
        }

        let today = MoodCheckIn(mood: draft.mood, energy: draft.energy, notes: draft.notes).localDateString
        let fileURL = journalDirectory.appendingPathComponent("\(today).md")
        NSWorkspace.shared.open(fileURL)
    }

    func appendWeeklyInsightsAndOpenTodayJournal() {
        guard let journalDirectory = resolution.journalDirectory else {
            errorMessage = "No journal directory is configured yet."
            saveMessage = nil
            return
        }

        let today = Date()
        do {
            _ = try appendWeeklyInsights(endingOn: today, appendTo: today, journalDirectory: journalDirectory)
            saveMessage = "Weekly insights appended."
            errorMessage = nil
            openTodayJournal()
        } catch {
            errorMessage = "Weekly insights failed: \(error.localizedDescription)"
            saveMessage = nil
        }
    }

    func openDatabaseFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([resolution.databaseURL])
    }

    func latestStatusItemSummary() -> StatusItemSummary? {
        let localDate = MoodCheckIn(mood: draft.mood, energy: draft.energy, notes: "").localDateString
        guard let summary = try? database.latestCheckInSummary(localDate: localDate) else {
            return nil
        }

        return StatusItemSummary(
            recordedAt: summary.recordedAt,
            moodValue: summary.moodValue,
            energyValue: summary.energyValue
        )
    }

    func bindPresentationHandlers(
        openMainWindow: @escaping () -> Void,
        openInsightsWindow: @escaping () -> Void,
        toggleQuickCheckIn: @escaping () -> Void,
        toggleQuickNote: @escaping () -> Void,
        presentReminderPanel: @escaping () -> Void,
        dismissReminderPanel: @escaping () -> Void
    ) {
        openMainWindowHandler = openMainWindow
        openInsightsWindowHandler = openInsightsWindow
        toggleQuickCheckInHandler = toggleQuickCheckIn
        toggleQuickNoteHandler = toggleQuickNote
        presentReminderPanelHandler = presentReminderPanel
        dismissReminderPanelHandler = dismissReminderPanel
    }

    func openMainWindow() {
        dismissReminderPanel()
        openMainWindowHandler?()
    }

    func openInsightsWindow() {
        dismissReminderPanel()
        openInsightsWindowHandler?()
    }

    func insightsChartData(days: Int) -> InsightsChartModel {
        let calendar = Calendar.current
        let referenceDate = Date()
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: endDay) ?? endDay
        let startLocalDate = InsightsEngine.localDateString(for: startDay, calendar: calendar)
        let endLocalDate = InsightsEngine.localDateString(for: endDay, calendar: calendar)
        let checkIns = (try? database.checkIns(from: startLocalDate, through: endLocalDate)) ?? []
        let snapshots = (try? database.fitbitSnapshots(from: startLocalDate, through: endLocalDate)) ?? []
        return InsightsChartModel.make(
            checkIns: checkIns,
            snapshots: snapshots,
            days: days,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func toggleQuickCheckIn() {
        toggleQuickCheckInHandler?()
    }

    func toggleQuickNote() {
        toggleQuickNoteHandler?()
    }

    func presentReminderPanel() {
        presentReminderPanelHandler?()
    }

    func dismissReminderPanel() {
        dismissReminderPanelHandler?()
    }

    func triggerReminderNow() {
        let bucket = Self.reminderBucket(for: Date())
        lastReminderBucket = bucket
        clearTransientCheckInMessages()
        presentReminderPanel()
        checkInsDidChange?()
        postReminderNotification(bucket: bucket)
    }

    func clearTransientCheckInMessages() {
        saveMessage = nil
        errorMessage = nil
    }

    func preparePanelCheckIn() {
        panelActiveRow = .mood
        isPanelNotesFocused = false
    }

    func setPanelValue(row: PanelActiveRow, value: Int) {
        let clampedValue = min(5, max(1, value))
        switch row {
        case .mood:
            draft.mood = MoodLevel(rawValue: clampedValue) ?? draft.mood
        case .energy:
            draft.energy = EnergyLevel(rawValue: clampedValue) ?? draft.energy
        }
    }

    func changePanelValue(row: PanelActiveRow, delta: Int) {
        let currentValue: Int
        switch row {
        case .mood:
            currentValue = draft.mood.rawValue
        case .energy:
            currentValue = draft.energy.rawValue
        }
        setPanelValue(row: row, value: currentValue + delta)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isSyncingLaunchAtLogin else { return }
        do {
            if enabled {
                try loginService.register()
            } else {
                try loginService.unregister()
            }
            refreshLaunchAtLoginState()
        } catch {
            refreshLaunchAtLoginState()
            errorMessage = "Couldn't update login item: \(error.localizedDescription)"
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }

    func restartApplication() {
        let bundleURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [bundleURL.path]

        do {
            try process.run()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.terminate(nil)
            }
        } catch {
            errorMessage = "Couldn't restart app: \(error.localizedDescription)"
        }
    }

    private func refreshResolution() {
        resolution = resolver.resolve()
        journalDirectoryDisplay = resolution.journalDirectory?.path ?? "Not configured"
        databasePathDisplay = resolution.databaseURL.path
        saveMessage = nil
        errorMessage = nil
    }

    private func autoAppendWeeklyInsightsIfNeeded(after checkIn: MoodCheckIn) {
        guard let journalDirectory = resolution.journalDirectory else { return }

        let currentISOWeek = InsightsEngine.isoWeekString(for: checkIn.recordedAt)
        let lastISOWeek = UserDefaults.standard.string(forKey: Self.lastInsightsISOWeekKey)
        guard InsightsEngine.shouldGenerateWeeklyInsights(
            lastGeneratedISOWeek: lastISOWeek,
            currentISOWeek: currentISOWeek
        ) else {
            return
        }

        do {
            let range = InsightsEngine.completedSevenDayRange(before: checkIn.recordedAt)
            _ = try appendWeeklyInsights(
                start: range.start,
                end: range.end,
                appendTo: checkIn.recordedAt,
                journalDirectory: journalDirectory
            )
            UserDefaults.standard.set(currentISOWeek, forKey: Self.lastInsightsISOWeekKey)
            saveMessage = "\(saveMessage ?? "Saved") · weekly insights appended"
        } catch {
            saveMessage = "\(saveMessage ?? "Saved") · weekly insights failed: \(error.localizedDescription)"
        }
    }

    private func appendWeeklyInsights(endingOn endDate: Date, appendTo appendDate: Date, journalDirectory: URL) throws -> URL {
        let range = InsightsEngine.trailingSevenDayRange(endingOn: endDate)
        return try appendWeeklyInsights(start: range.start, end: range.end, appendTo: appendDate, journalDirectory: journalDirectory)
    }

    private func appendWeeklyInsights(start: Date, end: Date, appendTo appendDate: Date, journalDirectory: URL) throws -> URL {
        let startLocalDate = InsightsEngine.localDateString(for: start)
        let endLocalDate = InsightsEngine.localDateString(for: end)
        let checkIns = try database.checkIns(from: startLocalDate, through: endLocalDate)
        let snapshots = try database.fitbitSnapshots(from: startLocalDate, through: endLocalDate)
        let insights = InsightsEngine.makeWeeklyInsights(
            checkIns: checkIns,
            snapshots: snapshots,
            startDate: startLocalDate,
            endDate: endLocalDate
        )
        let markdown = InsightsEngine.renderMarkdown(insights)
        let fileURL = try journalWriter.append(weeklyInsights: markdown, for: appendDate, to: journalDirectory)
        journalDirectoryDisplay = journalDirectory.path
        return fileURL
    }

    private func refreshLaunchAtLoginState() {
        isSyncingLaunchAtLogin = true
        defer { isSyncingLaunchAtLogin = false }

        switch loginService.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginStatusMessage = "Launch at login is enabled."
        case .requiresApproval:
            launchAtLoginEnabled = true
            launchAtLoginStatusMessage = "Login item needs approval in System Settings."
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginStatusMessage = "Launch at login is off."
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginStatusMessage = "macOS couldn't register this app yet. Moving it to /Applications can help."
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginStatusMessage = nil
        }
    }

    private func ensureNotificationAuthorization() {
        Task { @MainActor in
            let settings = await notificationCenter.notificationSettings()
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationStatusMessage = nil
                return
            case .notDetermined:
                do {
                    let granted = try await notificationCenter.requestAuthorization(options: [.alert])
                    if granted {
                        notificationStatusMessage = nil
                        rescheduleReminder()
                    } else {
                        notificationStatusMessage = "Notifications were not allowed. Enable them in System Settings to receive hourly checks."
                    }
                } catch {
                    notificationStatusMessage = "Notification permission request failed: \(error.localizedDescription)"
                }
            case .denied:
                notificationStatusMessage = "Notifications are disabled for FitbitAirMoodBar in System Settings."
            @unknown default:
                return
            }
        }
    }

    private func rescheduleReminder() {
        reminderTimer?.invalidate()
        reminderTimer = nil
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.hourlyReminderNotificationIdentifier])

        guard reminderEnabled else { return }
        scheduleHourlyNotification()

        guard !quietHourlyReminders else { return }
        scheduleHourlyPanelTimer()
    }

    private func scheduleHourlyPanelTimer() {
        let now = Date()
        let calendar = Calendar.current
        let nextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)

        let interval = max(5, nextHour.timeIntervalSinceNow)
        reminderTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.fireReminder()
                self?.rescheduleReminder()
            }
        }
        if let reminderTimer {
            RunLoop.main.add(reminderTimer, forMode: .common)
        }
    }

    private func fireReminder() {
        let bucket = Self.reminderBucket(for: Date())
        guard bucket != lastReminderBucket else { return }
        lastReminderBucket = bucket

        guard !ReminderSuppression.shouldSuppress(lastCheckInAt: Self.storedLastCheckInAt(), now: Date()) else {
            return
        }

        presentReminderPanel()
        checkInsDidChange?()
    }

    nonisolated static func storedLastCheckInAt() -> Date? {
        let stored = UserDefaults.standard.double(forKey: lastCheckInAtKey)
        guard stored > 0 else { return nil }
        return Date(timeIntervalSince1970: stored)
    }

    private func scheduleHourlyNotification() {
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: DateComponents(minute: 0, second: 0),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Self.hourlyReminderNotificationIdentifier,
            content: makeReminderNotificationContent(),
            trigger: trigger
        )

        addNotificationRequest(request)
    }

    private func postReminderNotification(bucket: String) {
        let request = UNNotificationRequest(
            identifier: "\(Self.manualReminderNotificationPrefix)\(bucket)",
            content: makeReminderNotificationContent(),
            trigger: nil
        )
        addNotificationRequest(request)
    }

    private func makeReminderNotificationContent() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Quick Check-In"
        content.body = quietHourlyReminders
            ? "Mood 3 / Energy 3. Tap when you have a moment."
            : "How are you feeling right now? Save a quick mood and energy snapshot."
        content.interruptionLevel = .active
        content.sound = nil
        return content
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) {
        notificationCenter.add(request) { [weak self] error in
            guard let error else { return }
            Task { @MainActor in
                self?.notificationStatusMessage = "Couldn't schedule hourly check-in: \(error.localizedDescription)"
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier == Self.hourlyReminderNotificationIdentifier,
           ReminderSuppression.shouldSuppress(lastCheckInAt: Self.storedLastCheckInAt(), now: Date()) {
            return []
        }
        return [.banner]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            presentReminderPanel()
        }
    }

    private static func reminderBucket(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func localTimeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private static func byteCountString(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct ReminderSuppression {
    static let windowMinutes = 45

    static func shouldSuppress(lastCheckInAt: Date?, now: Date) -> Bool {
        guard let lastCheckInAt else { return false }
        let elapsedMinutes = now.timeIntervalSince(lastCheckInAt) / 60
        return elapsedMinutes >= 0 && elapsedMinutes < Double(windowMinutes)
    }
}

struct FitbitSnapshotFreshness {
    static let staleAfterMinutes = 60

    static func shouldAutoSync(snapshotAgeMinutes: Int?) -> Bool {
        guard let snapshotAgeMinutes else { return true }
        return snapshotAgeMinutes > staleAfterMinutes
    }

    static func shouldAutoSync(snapshotRecordedAt: Date?, now: Date) -> Bool {
        guard let snapshotRecordedAt else { return true }
        let ageMinutes = Int(now.timeIntervalSince(snapshotRecordedAt) / 60)
        return shouldAutoSync(snapshotAgeMinutes: ageMinutes)
    }
}
