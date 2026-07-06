import Foundation

/// Pure, non-isolated aggregation of check-in and Fitbit data into chart-ready
/// arrays for the Insights window. All date math flows through the supplied
/// calendar so tests can pin a fixed timezone.
struct InsightsChartModel: Equatable {
    struct DailyAverage: Equatable, Identifiable {
        let date: Date
        let mood: Double
        let energy: Double
        var id: Date { date }
    }

    struct BucketAverage: Equatable, Identifiable {
        let bucket: TimeOfDayBucket
        let mood: Double
        let energy: Double
        var id: String { bucket.rawValue }
    }

    struct SleepMoodPoint: Equatable, Identifiable {
        let date: Date
        let sleep: Double
        let mood: Double
        var id: Date { date }
    }

    static let minimumSleepMoodPairs = 5

    let rangeStart: Date
    let rangeEnd: Date
    let totalCheckIns: Int
    let dailyAverages: [DailyAverage]
    let bucketAverages: [BucketAverage]
    let sleepMoodPoints: [SleepMoodPoint]
    let correlation: Double?

    var hasData: Bool { totalCheckIns > 0 }
    var hasEnoughSleepPairs: Bool { sleepMoodPoints.count >= Self.minimumSleepMoodPairs }

    static func make(
        checkIns: [InsightCheckIn],
        snapshots: [InsightFitbitSnapshot],
        days: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> InsightsChartModel {
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: endDay) ?? endDay
        let startLocalDate = InsightsEngine.localDateString(for: startDay, calendar: calendar)
        let endLocalDate = InsightsEngine.localDateString(for: endDay, calendar: calendar)

        let rangedCheckIns = checkIns.filter { $0.localDate >= startLocalDate && $0.localDate <= endLocalDate }
        let rangedSnapshots = snapshots.filter { $0.localDate >= startLocalDate && $0.localDate <= endLocalDate }

        let byDay = Dictionary(grouping: rangedCheckIns, by: \.localDate)
        let dayMood = byDay.mapValues { mean($0.map(\.moodValue)) }
        let dayEnergy = byDay.mapValues { mean($0.map(\.energyValue)) }

        let dailyAverages: [DailyAverage] = byDay.keys.compactMap { localDate in
            guard
                let date = InsightsEngine.parseLocalDate(localDate, calendar: calendar),
                let mood = dayMood[localDate],
                let energy = dayEnergy[localDate]
            else {
                return nil
            }
            return DailyAverage(date: date, mood: mood, energy: energy)
        }.sorted { $0.date < $1.date }

        let bucketAverages = TimeOfDayBucket.allCases.compactMap { bucket -> BucketAverage? in
            let bucketCheckIns = rangedCheckIns.filter {
                TimeOfDayBucket.bucket(for: $0.recordedAt, calendar: calendar) == bucket
            }
            guard !bucketCheckIns.isEmpty else { return nil }
            return BucketAverage(
                bucket: bucket,
                mood: mean(bucketCheckIns.map(\.moodValue)),
                energy: mean(bucketCheckIns.map(\.energyValue))
            )
        }

        let sleepPairs: [(String, Double)] = rangedSnapshots.compactMap { snapshot in
            guard let metric = InsightsEngine.sleepMetric(fromPayloadJSON: snapshot.payloadJSON) else { return nil }
            return (snapshot.localDate, metric)
        }
        let sleepByDate = Dictionary(sleepPairs, uniquingKeysWith: { _, latest in latest })
        let sleepMoodPoints: [SleepMoodPoint] = dayMood.compactMap { localDate, mood in
            guard
                let sleep = sleepByDate[localDate],
                let date = InsightsEngine.parseLocalDate(localDate, calendar: calendar)
            else {
                return nil
            }
            return SleepMoodPoint(date: date, sleep: sleep, mood: mood)
        }.sorted { $0.date < $1.date }

        let correlation = sleepMoodPoints.count >= minimumSleepMoodPairs
            ? InsightsEngine.pearsonCorrelation(sleepMoodPoints.map { ($0.sleep, $0.mood) })
            : nil

        return InsightsChartModel(
            rangeStart: startDay,
            rangeEnd: endDay,
            totalCheckIns: rangedCheckIns.count,
            dailyAverages: dailyAverages,
            bucketAverages: bucketAverages,
            sleepMoodPoints: sleepMoodPoints,
            correlation: correlation
        )
    }

    private static func mean(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
