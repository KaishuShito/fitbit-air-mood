import Foundation
import SQLite3
import Testing
@testable import FitbitAirMoodBar

struct FitbitAirMoodBarTests {
    @Test
    func journalWriterAppendsCheckInToDailyJournal() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let checkIn = MoodCheckIn(
            recordedAt: Date(timeIntervalSince1970: 1_713_654_000),
            mood: .good,
            energy: .steady,
            notes: "Felt surprisingly focused."
        )

        let writer = JournalWriter()
        let fileURL = try writer.append(checkIn: checkIn, to: tempDir)
        let text = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(fileURL.lastPathComponent == "\(checkIn.localDateString).md")
        #expect(text.contains("## Mood Check-In - \(checkIn.localTimestampString)"))
        #expect(text.contains("- Mood (valence): 🙂 4/5 Good"))
        #expect(text.contains("- Energy (arousal): ⚡️ 3/5 Steady"))
        #expect(text.contains("Felt surprisingly focused."))
    }

    @Test
    func sqliteStoreCreatesTableAndSavesCheckIn() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let journalURL = tempDir.appendingPathComponent("2026-04-21.md")

        let store = try SQLiteStore(databaseURL: databaseURL)
        let checkIn = MoodCheckIn(
            recordedAt: Date(timeIntervalSince1970: 1_713_654_000),
            mood: .neutral,
            energy: .high,
            notes: "A little flat but moving."
        )

        try store.insert(checkIn: checkIn, journalFileURL: journalURL)

        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        #expect((attributes[.size] as? NSNumber)?.intValue ?? 0 > 0)
    }

    @Test
    func sqliteStoreMigratesOldCheckInSchemaWithoutLosingRows() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let existingID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!

        try createOldSchemaDatabase(at: databaseURL, checkInID: existingID)

        do {
            let store = try SQLiteStore(databaseURL: databaseURL)
            #expect(try store.checkInCount() == 1)
            #expect(try store.savedFitbitSnapshotLink(checkInID: existingID) == nil)
        }

        let reopenedStore = try SQLiteStore(databaseURL: databaseURL)
        #expect(try reopenedStore.checkInCount() == 1)
        #expect(try reopenedStore.savedFitbitSnapshotLink(checkInID: existingID) == nil)
    }

    @Test
    func sqliteStoreUpsertsOneFitbitSnapshotPerDay() throws {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let recordedAt = Date(timeIntervalSince1970: 1_780_286_400)

        try store.upsertFitbitSnapshot(FitbitDailySnapshot(recordedAt: recordedAt, payloadJSON: #"{"steps":100}"#))
        try store.upsertFitbitSnapshot(FitbitDailySnapshot(recordedAt: recordedAt.addingTimeInterval(60), payloadJSON: #"{"steps":125}"#))

        #expect(try store.fitbitSnapshotCount() == 1)
    }

    @Test
    func sqliteStoreLinksFreshTodaySnapshotWhenSavingCheckIn() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let journalURL = tempDir.appendingPathComponent("2026-04-21.md")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let now = Date(timeIntervalSince1970: 1_780_286_400)
        let snapshotRecordedAt = now.addingTimeInterval(-30 * 60)
        let checkIn = MoodCheckIn(
            recordedAt: now,
            mood: .good,
            energy: .high,
            notes: "Ready for the next loop."
        )

        try store.upsertFitbitSnapshot(FitbitDailySnapshot(recordedAt: snapshotRecordedAt, payloadJSON: #"{"readiness":82}"#))
        let link = try store.currentFitbitSnapshotLink(for: checkIn, now: now)
        try store.insert(checkIn: checkIn, journalFileURL: journalURL, fitbitSnapshotLink: link)

        #expect(try store.savedFitbitSnapshotLink(checkInID: checkIn.id) == FitbitSnapshotLink(
            localDateString: checkIn.localDateString,
            ageMinutes: 30
        ))
    }

    @Test
    func sqliteStoreLeavesFitbitLinkNullWhenNoSnapshotExists() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let journalURL = tempDir.appendingPathComponent("2026-04-21.md")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let checkIn = MoodCheckIn(
            recordedAt: Date(timeIntervalSince1970: 1_780_286_400),
            mood: .neutral,
            energy: .steady,
            notes: ""
        )

        let link = try store.currentFitbitSnapshotLink(for: checkIn, now: checkIn.recordedAt)
        try store.insert(checkIn: checkIn, journalFileURL: journalURL, fitbitSnapshotLink: link)

        #expect(link == nil)
        #expect(try store.savedFitbitSnapshotLink(checkInID: checkIn.id) == nil)
    }

    @Test
    func sqliteStoreLatestCheckInSummaryReturnsNewestSameDayCheckIn() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let journalURL = tempDir.appendingPathComponent("2026-04-21.md")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let first = MoodCheckIn(
            recordedAt: Date(timeIntervalSince1970: 1_780_286_400),
            mood: .low,
            energy: .steady,
            notes: "Earlier."
        )
        let latest = MoodCheckIn(
            recordedAt: first.recordedAt.addingTimeInterval(95 * 60),
            mood: .great,
            energy: .high,
            notes: "Later."
        )

        try store.insert(checkIn: first, journalFileURL: journalURL)
        try store.insert(checkIn: latest, journalFileURL: journalURL)

        let summary = try store.latestCheckInSummary(localDate: first.localDateString)
        #expect(summary?.recordedAt == latest.recordedAt)
        #expect(summary?.moodValue == 5)
        #expect(summary?.energyValue == 4)
    }

    @Test
    func sqliteStoreLatestCheckInSummaryReturnsNilForOtherDays() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let journalURL = tempDir.appendingPathComponent("2026-04-21.md")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let checkIn = MoodCheckIn(
            recordedAt: Date(timeIntervalSince1970: 1_780_286_400),
            mood: .neutral,
            energy: .steady,
            notes: ""
        )

        try store.insert(checkIn: checkIn, journalFileURL: journalURL)

        #expect(try store.latestCheckInSummary(localDate: "1900-01-01") == nil)
    }

    @Test
    func sqliteStoreReadsInsightRanges() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let journalURL = tempDir.appendingPathComponent("2026-06-24.md")
        let store = try SQLiteStore(databaseURL: databaseURL)
        let outside = MoodCheckIn(
            recordedAt: date("2026-06-21T09:00:00Z")!,
            mood: .low,
            energy: .low,
            notes: ""
        )
        let inside = MoodCheckIn(
            recordedAt: date("2026-06-24T09:00:00Z")!,
            mood: .great,
            energy: .high,
            notes: ""
        )

        try store.insert(checkIn: outside, journalFileURL: journalURL)
        try store.insert(checkIn: inside, journalFileURL: journalURL)
        try store.upsertFitbitSnapshot(FitbitDailySnapshot(recordedAt: outside.recordedAt, payloadJSON: #"{"sleep":[]}"#))
        try store.upsertFitbitSnapshot(FitbitDailySnapshot(recordedAt: inside.recordedAt, payloadJSON: #"{"sleep":[{"score":{"sleep_performance_percentage":88}}]}"#))

        let checkIns = try store.checkIns(from: "2026-06-22", through: "2026-06-28")
        let snapshots = try store.fitbitSnapshots(from: "2026-06-22", through: "2026-06-28")

        #expect(checkIns == [
            InsightCheckIn(recordedAt: inside.recordedAt, localDate: inside.localDateString, moodValue: 5, energyValue: 4),
        ])
        #expect(snapshots == [
            InsightFitbitSnapshot(localDate: inside.localDateString, payloadJSON: #"{"sleep":[{"score":{"sleep_performance_percentage":88}}]}"#),
        ])
    }

    @Test
    func statusItemRelativeTimeFormatting() {
        let now = Date(timeIntervalSince1970: 1_780_286_400)

        #expect(StatusItemDisplayLogic.relativeTimeString(from: now, now: now) == "0m ago")
        #expect(StatusItemDisplayLogic.relativeTimeString(from: now.addingTimeInterval(-59 * 60), now: now) == "59m ago")
        #expect(StatusItemDisplayLogic.relativeTimeString(from: now.addingTimeInterval(-60 * 60), now: now) == "1h 0m ago")
        #expect(StatusItemDisplayLogic.relativeTimeString(from: now.addingTimeInterval(-95 * 60), now: now) == "1h 35m ago")
    }

    @Test
    func statusItemButtonTitleUsesMoodEmojiOrFallback() {
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 1) == "😞")
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 2) == "🙁")
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 3) == "😐")
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 4) == "🙂")
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 5) == "😄")
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 0) == nil)
        #expect(StatusItemDisplayLogic.buttonTitle(moodValue: 6) == nil)
    }

    @Test
    func staleOrMissingFitbitSnapshotTriggersAutoSyncDecision() {
        let now = Date(timeIntervalSince1970: 1_780_286_400)

        #expect(FitbitSnapshotFreshness.shouldAutoSync(snapshotRecordedAt: nil, now: now))
        #expect(!FitbitSnapshotFreshness.shouldAutoSync(snapshotRecordedAt: now.addingTimeInterval(-60 * 60), now: now))
        #expect(FitbitSnapshotFreshness.shouldAutoSync(snapshotRecordedAt: now.addingTimeInterval(-61 * 60), now: now))
    }

    @Test
    func recentCheckInSuppressesHourlyReminder() {
        let now = Date(timeIntervalSince1970: 1_780_286_400)

        #expect(!ReminderSuppression.shouldSuppress(lastCheckInAt: nil, now: now))
        #expect(ReminderSuppression.shouldSuppress(lastCheckInAt: now.addingTimeInterval(-10 * 60), now: now))
        #expect(ReminderSuppression.shouldSuppress(lastCheckInAt: now.addingTimeInterval(-44 * 60), now: now))
        #expect(!ReminderSuppression.shouldSuppress(lastCheckInAt: now.addingTimeInterval(-45 * 60), now: now))
        #expect(!ReminderSuppression.shouldSuppress(lastCheckInAt: now.addingTimeInterval(-90 * 60), now: now))
        #expect(!ReminderSuppression.shouldSuppress(lastCheckInAt: now.addingTimeInterval(5 * 60), now: now))
    }

    @Test
    func insightsEngineComputesWeeklyStats() throws {
        let calendar = utcCalendar()
        let checkIns = syntheticWeekCheckIns()
        let snapshots = [
            snapshot("2026-06-22", sleepPerformance: 70),
            snapshot("2026-06-23", sleepPerformance: 60),
            snapshot("2026-06-24", sleepPerformance: 90),
            snapshot("2026-06-25", sleepPerformance: 80),
            snapshot("2026-06-26", sleepPerformance: 50),
            snapshot("2026-06-27", sleepPerformance: 65),
        ]

        let insights = InsightsEngine.makeWeeklyInsights(
            checkIns: checkIns,
            snapshots: snapshots,
            startDate: "2026-06-22",
            endDate: "2026-06-28",
            calendar: calendar
        )

        #expect(insights.totalCheckIns == 7)
        #expect(abs((insights.checkInsPerDay ?? 0) - 1.0) < 0.001)
        #expect(abs((insights.moodAverage ?? 0) - 3.142857) < 0.001)
        #expect(abs((insights.energyAverage ?? 0) - 2.857142) < 0.001)
        #expect(insights.bestDay == WeeklyInsights.DayAverage(weekdayName: "Wednesday", value: 5.0))
        #expect(insights.toughestDay == WeeklyInsights.DayAverage(weekdayName: "Friday", value: 1.0))
        #expect(insights.timeOfDayAverages == [
            WeeklyInsights.TimeOfDayAverage(bucket: .morning, moodAverage: 4.0, energyAverage: 3.5, count: 2),
            WeeklyInsights.TimeOfDayAverage(bucket: .afternoon, moodAverage: 4.0, energyAverage: 3.5, count: 2),
            WeeklyInsights.TimeOfDayAverage(bucket: .evening, moodAverage: 2.0, energyAverage: 2.0, count: 3),
        ])
        #expect((insights.sleepMoodCorrelation ?? 0) > 0.98)
    }

    @Test
    func insightsEngineUsesSparseDataMessageWithoutFakeStats() {
        let insights = InsightsEngine.makeWeeklyInsights(
            checkIns: Array(syntheticWeekCheckIns().prefix(3)),
            snapshots: [],
            startDate: "2026-06-22",
            endDate: "2026-06-28",
            calendar: utcCalendar()
        )

        #expect(insights.moodAverage == nil)
        #expect(insights.timeOfDayAverages.isEmpty)
        #expect(InsightsEngine.renderMarkdown(insights) == """
        ## 🧭 Weekly Mood Insights (2026-06-22 – 2026-06-28)

        - Not enough check-ins this week yet (3 so far) — keep going.
        """)
    }

    @Test
    func insightsEngineOmitsCorrelationBelowFivePairedDays() {
        let snapshots = [
            snapshot("2026-06-22", sleepPerformance: 70),
            snapshot("2026-06-23", sleepPerformance: 60),
            snapshot("2026-06-24", sleepPerformance: 90),
            snapshot("2026-06-25", sleepPerformance: 80),
        ]

        let insights = InsightsEngine.makeWeeklyInsights(
            checkIns: syntheticWeekCheckIns(),
            snapshots: snapshots,
            startDate: "2026-06-22",
            endDate: "2026-06-28",
            calendar: utcCalendar()
        )

        #expect(insights.sleepMoodCorrelation == nil)
        #expect(!InsightsEngine.renderMarkdown(insights).contains("Sleep and mood"))
    }

    @Test
    func insightsRendererProducesCompactMarkdownSnapshot() {
        let insights = WeeklyInsights(
            startDate: "2026-06-22",
            endDate: "2026-06-28",
            totalCheckIns: 7,
            checkInsPerDay: 1.0,
            moodAverage: 3.142857,
            energyAverage: 2.857142,
            bestDay: WeeklyInsights.DayAverage(weekdayName: "Wednesday", value: 5.0),
            toughestDay: WeeklyInsights.DayAverage(weekdayName: "Friday", value: 1.0),
            timeOfDayAverages: [
                WeeklyInsights.TimeOfDayAverage(bucket: .morning, moodAverage: 4.0, energyAverage: 3.5, count: 2),
                WeeklyInsights.TimeOfDayAverage(bucket: .afternoon, moodAverage: 4.0, energyAverage: 3.5, count: 2),
                WeeklyInsights.TimeOfDayAverage(bucket: .evening, moodAverage: 2.0, energyAverage: 2.0, count: 3),
            ],
            sleepMoodCorrelation: 0.56
        )

        #expect(InsightsEngine.renderMarkdown(insights) == """
        ## 🧭 Weekly Mood Insights (2026-06-22 – 2026-06-28)

        - Check-ins: 7 total (1.0 per day)
        - Averages: mood 3.1/5, energy 2.9/5
        - Best mood day: Wednesday (5.0/5); toughest: Friday (1.0/5)
        - Time of day: morning mood 4.0, energy 3.5; afternoon mood 4.0, energy 3.5; evening mood 2.0, energy 2.0
        - Sleep and mood moved moderately together this week (r=0.6).
        """)
    }

    @Test
    func insightsISOWeekGuardFiresOnlyForNewWeek() throws {
        let calendar = utcCalendar()
        let firstWeekDate = try #require(date("2026-06-29T09:00:00Z"))
        let sameWeekDate = try #require(date("2026-07-02T09:00:00Z"))
        let nextWeekDate = try #require(date("2026-07-06T09:00:00Z"))
        let firstWeek = InsightsEngine.isoWeekString(for: firstWeekDate, calendar: calendar)

        #expect(firstWeek == "2026-W27")
        #expect(InsightsEngine.isoWeekString(for: sameWeekDate, calendar: calendar) == firstWeek)
        #expect(InsightsEngine.isoWeekString(for: nextWeekDate, calendar: calendar) == "2026-W28")
        #expect(InsightsEngine.shouldGenerateWeeklyInsights(lastGeneratedISOWeek: nil, currentISOWeek: firstWeek))
        #expect(!InsightsEngine.shouldGenerateWeeklyInsights(lastGeneratedISOWeek: firstWeek, currentISOWeek: firstWeek))
        #expect(InsightsEngine.shouldGenerateWeeklyInsights(lastGeneratedISOWeek: firstWeek, currentISOWeek: "2026-W28"))
    }

    @Test
    func journalWriterAppendsWeeklyInsightsToDailyJournalAndPreservesContent() throws {
        let tempDir = try makeTempDir()
        let writer = JournalWriter()
        let appendDate = try #require(date("2026-07-02T09:00:00Z"))
        let localDate = InsightsEngine.localDateString(for: appendDate)
        let fileURL = tempDir.appendingPathComponent("\(localDate).md")
        try "Existing journal text\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let writtenURL = try writer.append(
            weeklyInsights: "## 🧭 Weekly Mood Insights (2026-06-25 – 2026-07-01)\n\n- Check-ins: 5 total (0.7 per day)",
            for: appendDate,
            to: tempDir
        )
        let text = try String(contentsOf: writtenURL, encoding: .utf8)

        #expect(writtenURL == fileURL)
        #expect(text.hasPrefix("Existing journal text\n\n"))
        #expect(text.contains("## 🧭 Weekly Mood Insights (2026-06-25 – 2026-07-01)"))
        #expect(text.hasSuffix("- Check-ins: 5 total (0.7 per day)\n"))
    }

    @Test
    func sleepMetricPrefersPerformanceAndFallsBackToDuration() {
        #expect(InsightsEngine.sleepMetric(fromPayloadJSON: #"{"sleep":[{"score":{"sleep_performance_percentage":82.5,"stage_summary":{"total_in_bed_time_milli":28800000}}}]}"#) == 82.5)
        #expect(InsightsEngine.sleepMetric(fromPayloadJSON: #"{"sleep":[{"score":{"stage_summary":{"total_light_sleep_time_milli":14400000,"total_slow_wave_sleep_time_milli":5400000,"total_rem_sleep_time_milli":7200000}}}]}"#) == 7.5)
    }

    @Test
    func panelDigitSetsActiveRowAndAdvancesFromMood() {
        let actions = PanelKeyRouter.actions(for: .digit(4), activeRow: .mood, notesFocused: false)

        #expect(actions == [
            .setValue(row: .mood, value: 4),
            .setActiveRow(.energy),
        ])
    }

    @Test
    func panelDigitSetsEnergyAndFocusesNotes() {
        let actions = PanelKeyRouter.actions(for: .digit(2), activeRow: .energy, notesFocused: false)

        #expect(actions == [
            .setValue(row: .energy, value: 2),
            .focusNotes,
        ])
    }

    @Test
    func panelRowAndArrowKeysChangeScalesOnlyOutsideNotes() {
        #expect(PanelKeyRouter.actions(for: .tab, activeRow: .mood, notesFocused: false) == [.setActiveRow(.energy)])
        #expect(PanelKeyRouter.actions(for: .up, activeRow: .energy, notesFocused: false) == [.setActiveRow(.mood)])
        #expect(PanelKeyRouter.actions(for: .left, activeRow: .mood, notesFocused: false) == [.changeValue(row: .mood, delta: -1)])
        #expect(PanelKeyRouter.actions(for: .right, activeRow: .energy, notesFocused: false) == [.changeValue(row: .energy, delta: 1)])
        #expect(PanelKeyRouter.actions(for: .digit(5), activeRow: .mood, notesFocused: true).isEmpty)
    }

    @Test
    func panelNoteSaveAndEscapeRespectNotesFocus() {
        #expect(PanelKeyRouter.actions(for: .note, activeRow: .mood, notesFocused: false) == [.focusNotes])
        #expect(PanelKeyRouter.actions(for: .return, activeRow: .mood, notesFocused: false) == [.save])
        #expect(PanelKeyRouter.actions(for: .return, activeRow: .mood, notesFocused: true).isEmpty)
        #expect(PanelKeyRouter.actions(for: .commandReturn, activeRow: .mood, notesFocused: true) == [.saveFromNotes])
        #expect(PanelKeyRouter.actions(for: .escape, activeRow: .mood, notesFocused: true) == [.leaveNotes])
        #expect(PanelKeyRouter.actions(for: .escape, activeRow: .mood, notesFocused: false) == [.dismiss])
    }

    @Test
    func insightsChartModelAveragesMultipleCheckInsPerDayAndSkipsMissingDays() {
        let calendar = utcCalendar()
        let checkIns = [
            insightCheckIn("2026-06-24T09:00:00Z", localDate: "2026-06-24", mood: 4, energy: 2),
            insightCheckIn("2026-06-24T20:00:00Z", localDate: "2026-06-24", mood: 2, energy: 4),
            insightCheckIn("2026-06-26T13:00:00Z", localDate: "2026-06-26", mood: 5, energy: 5),
        ]

        let model = InsightsChartModel.make(
            checkIns: checkIns,
            snapshots: [],
            days: 7,
            referenceDate: date("2026-06-28T12:00:00Z")!,
            calendar: calendar
        )

        #expect(model.totalCheckIns == 3)
        #expect(model.hasData)
        // Two days have data (06-24, 06-26); 06-25 and others have no fabricated points.
        #expect(model.dailyAverages.map { InsightsEngine.localDateString(for: $0.date, calendar: calendar) } == ["2026-06-24", "2026-06-26"])
        #expect(model.dailyAverages[0].mood == 3.0)
        #expect(model.dailyAverages[0].energy == 3.0)
        #expect(model.dailyAverages[1].mood == 5.0)
    }

    @Test
    func insightsChartModelComputesGroupedBucketAverages() {
        let model = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: [],
            days: 30,
            referenceDate: date("2026-06-28T12:00:00Z")!,
            calendar: utcCalendar()
        )

        #expect(model.bucketAverages == [
            InsightsChartModel.BucketAverage(bucket: .morning, mood: 4.0, energy: 3.5),
            InsightsChartModel.BucketAverage(bucket: .afternoon, mood: 4.0, energy: 3.5),
            InsightsChartModel.BucketAverage(bucket: .evening, mood: 2.0, energy: 2.0),
        ])
    }

    @Test
    func insightsChartModelPairsSleepAndMoodWithCorrelationAboveFive() {
        let calendar = utcCalendar()
        let snapshots = [
            snapshot("2026-06-22", sleepPerformance: 70),
            snapshot("2026-06-23", sleepPerformance: 60),
            snapshot("2026-06-24", sleepPerformance: 90),
            snapshot("2026-06-25", sleepPerformance: 80),
            snapshot("2026-06-26", sleepPerformance: 50),
            snapshot("2026-06-27", sleepPerformance: 65),
        ]

        let model = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: snapshots,
            days: 30,
            referenceDate: date("2026-06-28T12:00:00Z")!,
            calendar: calendar
        )

        #expect(model.sleepMoodPoints.count == 6)
        #expect(model.hasEnoughSleepPairs)
        #expect((model.correlation ?? 0) > 0.98)
        // Points are sorted by date and carry the day's mood average.
        #expect(model.sleepMoodPoints.first?.sleep == 70)
        #expect(model.sleepMoodPoints.first?.mood == 3.5)
    }

    @Test
    func insightsChartModelOmitsCorrelationBelowFivePairedDays() {
        let snapshots = [
            snapshot("2026-06-22", sleepPerformance: 70),
            snapshot("2026-06-24", sleepPerformance: 90),
            snapshot("2026-06-26", sleepPerformance: 50),
        ]

        let model = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: snapshots,
            days: 30,
            referenceDate: date("2026-06-28T12:00:00Z")!,
            calendar: utcCalendar()
        )

        #expect(model.sleepMoodPoints.count == 3)
        #expect(!model.hasEnoughSleepPairs)
        #expect(model.correlation == nil)
    }

    @Test
    func insightsChartModelFiltersByRangeWindow() {
        let calendar = utcCalendar()
        let reference = date("2026-06-28T12:00:00Z")!

        let sevenDay = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: [],
            days: 7,
            referenceDate: reference,
            calendar: calendar
        )
        let thirtyDay = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: [],
            days: 30,
            referenceDate: reference,
            calendar: calendar
        )

        // 7-day window ends 06-28 and starts 06-22, so all seven synthetic days are in range.
        #expect(sevenDay.totalCheckIns == 7)
        #expect(thirtyDay.totalCheckIns == 7)

        // A tighter 3-day window (06-26..06-28) keeps only the later check-ins.
        let threeDay = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: [],
            days: 3,
            referenceDate: reference,
            calendar: calendar
        )
        #expect(threeDay.totalCheckIns == 2)
        #expect(threeDay.dailyAverages.map { InsightsEngine.localDateString(for: $0.date, calendar: calendar) } == ["2026-06-26", "2026-06-27"])
    }

    @Test
    func insightsChartModelReportsEmptyRange() {
        let model = InsightsChartModel.make(
            checkIns: syntheticWeekCheckIns(),
            snapshots: [],
            days: 7,
            referenceDate: date("2026-08-15T12:00:00Z")!,
            calendar: utcCalendar()
        )

        #expect(model.totalCheckIns == 0)
        #expect(!model.hasData)
        #expect(model.dailyAverages.isEmpty)
        #expect(model.bucketAverages.isEmpty)
        #expect(model.sleepMoodPoints.isEmpty)
    }

    @Test
    func quickNotesCRUDAndMigrationIdempotency() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")

        do {
            let store = try SQLiteStore(databaseURL: databaseURL)
            #expect(try store.quickNoteCount() == 0)

            try store.insertQuickNote(QuickNote(
                id: "note-1",
                content: "First note",
                createdAt: "2026-07-06T09:00:00.000+09:00",
                updatedAt: "2026-07-06T09:00:00.000+09:00",
                journalSavedAt: nil
            ))
            #expect(try store.quickNoteCount() == 1)
            #expect(try store.quickNotes().first?.content == "First note")
            #expect(try store.quickNotes().first?.journalSavedAt == nil)

            try store.updateQuickNoteContent(
                id: "note-1",
                content: "First note, edited",
                updatedAt: "2026-07-06T09:05:00.000+09:00"
            )
            #expect(try store.quickNotes().first?.content == "First note, edited")

            try store.markQuickNoteJournalSaved(id: "note-1", journalSavedAt: "2026-07-06T09:06:00.000+09:00")
            #expect(try store.quickNotes().first?.journalSavedAt == "2026-07-06T09:06:00.000+09:00")

            try store.deleteQuickNote(id: "note-1")
            #expect(try store.quickNoteCount() == 0)
        }

        // Reopening runs the additive migration again without failing or losing the table.
        let reopened = try SQLiteStore(databaseURL: databaseURL)
        #expect(try reopened.quickNoteCount() == 0)
        try reopened.insertQuickNote(QuickNote(
            id: "note-2",
            content: "After reopen",
            createdAt: "2026-07-06T10:00:00.000+09:00",
            updatedAt: "2026-07-06T10:00:00.000+09:00",
            journalSavedAt: nil
        ))
        #expect(try reopened.quickNoteCount() == 1)
    }

    @Test
    func quickNotesReturnMostRecentlyUpdatedFirst() throws {
        let tempDir = try makeTempDir()
        let databaseURL = tempDir.appendingPathComponent("checkins.sqlite3")
        let store = try SQLiteStore(databaseURL: databaseURL)

        try store.insertQuickNote(QuickNote(
            id: "older",
            content: "Older",
            createdAt: "2026-07-06T08:00:00.000+09:00",
            updatedAt: "2026-07-06T08:00:00.000+09:00",
            journalSavedAt: nil
        ))
        try store.insertQuickNote(QuickNote(
            id: "newer",
            content: "Newer",
            createdAt: "2026-07-06T07:00:00.000+09:00",
            updatedAt: "2026-07-06T09:30:00.000+09:00",
            journalSavedAt: nil
        ))

        #expect(try store.quickNotes().map(\.id) == ["newer", "older"])
        #expect(try store.mostRecentlyUpdatedQuickNote()?.id == "newer")
    }

    @Test
    func journalWriterAppendsQuickNoteAndPreservesExistingContent() throws {
        let tempDir = try makeTempDir()
        let writer = JournalWriter()
        let noteDate = try #require(date("2026-07-06T04:07:00Z"))
        let localDate = InsightsEngine.localDateString(for: noteDate)
        let fileURL = tempDir.appendingPathComponent("\(localDate).md")
        try "Existing journal text\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let writtenURL = try writer.append(quickNote: "Buy milk\nAnd eggs", at: noteDate, to: tempDir)
        let text = try String(contentsOf: writtenURL, encoding: .utf8)

        let expectedTime = localTimeString(for: noteDate)
        #expect(writtenURL == fileURL)
        #expect(text.hasPrefix("Existing journal text\n\n"))
        #expect(text.contains("### 📝 Note \(expectedTime)\n\nBuy milk\nAnd eggs"))
        #expect(text.hasSuffix("Buy milk\nAnd eggs\n"))
    }

    @Test
    func quickNoteDisplayTitleUsesFirstNonBlankLineOrUntitled() {
        #expect(QuickNote.displayTitle(for: "First line\nSecond line") == "First line")
        #expect(QuickNote.displayTitle(for: "\n\n  \nReal title\nmore") == "Real title")
        #expect(QuickNote.displayTitle(for: "  Padded title  \nbody") == "Padded title")
        #expect(QuickNote.displayTitle(for: "") == "Untitled")
        #expect(QuickNote.displayTitle(for: "   \n\t\n  ") == "Untitled")
    }

    @Test
    func quickNoteWordCountCountsWhitespaceSeparatedTokens() {
        #expect(QuickNoteModel.wordCount(in: "") == 0)
        #expect(QuickNoteModel.wordCount(in: "   \n ") == 0)
        #expect(QuickNoteModel.wordCount(in: "hello") == 1)
        #expect(QuickNoteModel.wordCount(in: "hello  world\nthird") == 3)
    }

    @Test
    func listSelectionMoveClampsAtBothEndsWithoutWrapping() {
        // Down at the last row stays put; up at the first row stays put.
        #expect(ListSelection.move(2, by: 1, count: 3) == 2)
        #expect(ListSelection.move(0, by: -1, count: 3) == 0)
        // Movement inside the range advances by one.
        #expect(ListSelection.move(0, by: 1, count: 3) == 1)
        #expect(ListSelection.move(2, by: -1, count: 3) == 1)
        // Larger deltas clamp rather than overshoot.
        #expect(ListSelection.move(0, by: 5, count: 3) == 2)
        #expect(ListSelection.move(2, by: -5, count: 3) == 0)
    }

    @Test
    func listSelectionClampResolvesEmptyAndOutOfRange() {
        #expect(ListSelection.clamp(5, count: 0) == 0)
        #expect(ListSelection.clamp(-3, count: 4) == 0)
        #expect(ListSelection.clamp(9, count: 4) == 3)
        #expect(ListSelection.clamp(2, count: 4) == 2)
    }

    @Test
    func listSelectionAfterDeleteAdjustsToNearestValidRow() {
        // Deleting the selected middle row keeps the slot (next row moves up).
        #expect(ListSelection.afterDelete(selected: 1, deletedIndex: 1, newCount: 3) == 1)
        // Deleting the selected last row moves selection to the new last row.
        #expect(ListSelection.afterDelete(selected: 3, deletedIndex: 3, newCount: 3) == 2)
        // Deleting a row above the caret shifts the caret up by one.
        #expect(ListSelection.afterDelete(selected: 2, deletedIndex: 0, newCount: 3) == 1)
        // Deleting a row below the caret leaves it untouched.
        #expect(ListSelection.afterDelete(selected: 1, deletedIndex: 2, newCount: 3) == 1)
        // Deleting the only row resolves to 0.
        #expect(ListSelection.afterDelete(selected: 0, deletedIndex: 0, newCount: 0) == 0)
    }

    @Test
    func quickNoteActionsAreContextDependentOnDeletableNote() {
        #expect(QuickNoteAction.available(hasDeletableNote: false) == [
            .newNote, .browseNotes, .saveToJournal, .closeWindow,
        ])
        #expect(QuickNoteAction.available(hasDeletableNote: true) == [
            .newNote, .browseNotes, .saveToJournal, .deleteNote, .closeWindow,
        ])
    }

    @Test
    func quickNoteActionsFilterMatchesTitleAndShortcut() {
        let all = QuickNoteAction.available(hasDeletableNote: true)
        #expect(QuickNoteAction.filtered(all, query: "") == all)
        #expect(QuickNoteAction.filtered(all, query: "save") == [.saveToJournal])
        #expect(QuickNoteAction.filtered(all, query: "⌘P") == [.browseNotes])
        #expect(QuickNoteAction.filtered(all, query: "zzz").isEmpty)
    }

    private func localTimeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func syntheticWeekCheckIns() -> [InsightCheckIn] {
        [
            insightCheckIn("2026-06-22T06:00:00Z", localDate: "2026-06-22", mood: 3, energy: 2),
            insightCheckIn("2026-06-22T13:00:00Z", localDate: "2026-06-22", mood: 4, energy: 4),
            insightCheckIn("2026-06-23T19:00:00Z", localDate: "2026-06-23", mood: 2, energy: 3),
            insightCheckIn("2026-06-24T09:00:00Z", localDate: "2026-06-24", mood: 5, energy: 5),
            insightCheckIn("2026-06-25T15:00:00Z", localDate: "2026-06-25", mood: 4, energy: 3),
            insightCheckIn("2026-06-26T22:00:00Z", localDate: "2026-06-26", mood: 1, energy: 2),
            insightCheckIn("2026-06-27T04:00:00Z", localDate: "2026-06-27", mood: 3, energy: 1),
        ]
    }

    private func insightCheckIn(_ isoString: String, localDate: String, mood: Int, energy: Int) -> InsightCheckIn {
        InsightCheckIn(
            recordedAt: date(isoString)!,
            localDate: localDate,
            moodValue: mood,
            energyValue: energy
        )
    }

    private func snapshot(_ localDate: String, sleepPerformance: Double) -> InsightFitbitSnapshot {
        InsightFitbitSnapshot(
            localDate: localDate,
            payloadJSON: #"{"sleep":[{"score":{"sleep_performance_percentage":\#(sleepPerformance)}}]}"#
        )
    }

    private func date(_ isoString: String) -> Date? {
        ISO8601DateFormatter().date(from: isoString)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func makeTempDir() throws -> URL {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func createOldSchemaDatabase(at databaseURL: URL, checkInID: UUID) throws {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw SQLiteTestError(message: "Failed to open test database")
        }
        defer { sqlite3_close(db) }

        try executeSQLite(db, """
        CREATE TABLE mood_checkins (
            id TEXT PRIMARY KEY,
            recorded_at TEXT NOT NULL,
            local_date TEXT NOT NULL,
            mood_value INTEGER NOT NULL,
            mood_label TEXT NOT NULL,
            energy_value INTEGER NOT NULL,
            energy_label TEXT NOT NULL,
            notes TEXT NOT NULL,
            journal_file_path TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try executeSQLite(db, """
        INSERT INTO mood_checkins (
            id, recorded_at, local_date, mood_value, mood_label,
            energy_value, energy_label, notes, journal_file_path
        ) VALUES (
            '\(checkInID.uuidString)', '2026-04-21T09:00:00.000+09:00', '2026-04-21',
            4, 'Good', 3, 'Steady', 'Existing row', '/tmp/2026-04-21.md'
        );
        """)
    }

    private func executeSQLite(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown SQLite test error"
            throw SQLiteTestError(message: message)
        }
    }
}

private struct SQLiteTestError: Error {
    let message: String
}
