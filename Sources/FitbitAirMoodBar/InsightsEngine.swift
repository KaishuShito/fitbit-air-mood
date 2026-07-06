import Foundation

struct InsightCheckIn: Equatable {
    let recordedAt: Date
    let localDate: String
    let moodValue: Int
    let energyValue: Int
}

struct InsightFitbitSnapshot: Equatable {
    let localDate: String
    let payloadJSON: String
}

struct WeeklyInsights: Equatable {
    struct DayAverage: Equatable {
        let weekdayName: String
        let value: Double
    }

    struct TimeOfDayAverage: Equatable {
        let bucket: TimeOfDayBucket
        let moodAverage: Double
        let energyAverage: Double
        let count: Int
    }

    let startDate: String
    let endDate: String
    let totalCheckIns: Int
    let checkInsPerDay: Double?
    let moodAverage: Double?
    let energyAverage: Double?
    let bestDay: DayAverage?
    let toughestDay: DayAverage?
    let timeOfDayAverages: [TimeOfDayAverage]
    let sleepMoodCorrelation: Double?
}

enum TimeOfDayBucket: String, CaseIterable {
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"

    static func bucket(for date: Date, calendar: Calendar = .current) -> TimeOfDayBucket {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<12:
            return .morning
        case 12..<18:
            return .afternoon
        default:
            return .evening
        }
    }
}

struct InsightsEngine {
    static let minimumCheckInsForStats = 5
    private static let minimumDaysForBestWorst = 2
    private static let minimumSleepMoodPairs = 5

    static func makeWeeklyInsights(
        checkIns: [InsightCheckIn],
        snapshots: [InsightFitbitSnapshot],
        startDate: String,
        endDate: String,
        calendar: Calendar = .current
    ) -> WeeklyInsights {
        let sortedCheckIns = checkIns.sorted { $0.recordedAt < $1.recordedAt }
        guard sortedCheckIns.count >= minimumCheckInsForStats else {
            return WeeklyInsights(
                startDate: startDate,
                endDate: endDate,
                totalCheckIns: sortedCheckIns.count,
                checkInsPerDay: nil,
                moodAverage: nil,
                energyAverage: nil,
                bestDay: nil,
                toughestDay: nil,
                timeOfDayAverages: [],
                sleepMoodCorrelation: nil
            )
        }

        let moodAverage = average(sortedCheckIns.map(\.moodValue))
        let energyAverage = average(sortedCheckIns.map(\.energyValue))
        let byDay = Dictionary(grouping: sortedCheckIns, by: \.localDate)
        let dayAverages = byDay.mapValues { average($0.map(\.moodValue)) }
        let sortedDayAverages = dayAverages.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value < rhs.value
        }

        let toughestDay = sortedDayAverages.count >= minimumDaysForBestWorst
            ? makeDayAverage(from: sortedDayAverages.first, calendar: calendar)
            : nil
        let bestDay = sortedDayAverages.count >= minimumDaysForBestWorst
            ? makeDayAverage(from: sortedDayAverages.last, calendar: calendar)
            : nil

        let timeOfDayAverages = TimeOfDayBucket.allCases.compactMap { bucket -> WeeklyInsights.TimeOfDayAverage? in
            let bucketCheckIns = sortedCheckIns.filter { TimeOfDayBucket.bucket(for: $0.recordedAt, calendar: calendar) == bucket }
            guard !bucketCheckIns.isEmpty else { return nil }
            return WeeklyInsights.TimeOfDayAverage(
                bucket: bucket,
                moodAverage: average(bucketCheckIns.map(\.moodValue)),
                energyAverage: average(bucketCheckIns.map(\.energyValue)),
                count: bucketCheckIns.count
            )
        }

        let sleepMetricPairs: [(String, Double)] = snapshots.compactMap { snapshot in
            guard let metric = sleepMetric(fromPayloadJSON: snapshot.payloadJSON) else { return nil }
            return (snapshot.localDate, metric)
        }
        let sleepMetricsByDate = Dictionary(sleepMetricPairs, uniquingKeysWith: { _, latest in latest })
        let sleepMoodPairs = dayAverages.compactMap { localDate, moodAverage -> (Double, Double)? in
            guard let sleepMetric = sleepMetricsByDate[localDate] else { return nil }
            return (sleepMetric, moodAverage)
        }
        let correlation = sleepMoodPairs.count >= minimumSleepMoodPairs
            ? pearsonCorrelation(sleepMoodPairs)
            : nil

        return WeeklyInsights(
            startDate: startDate,
            endDate: endDate,
            totalCheckIns: sortedCheckIns.count,
            checkInsPerDay: Double(sortedCheckIns.count) / 7.0,
            moodAverage: moodAverage,
            energyAverage: energyAverage,
            bestDay: bestDay,
            toughestDay: toughestDay,
            timeOfDayAverages: timeOfDayAverages,
            sleepMoodCorrelation: correlation
        )
    }

    static func renderMarkdown(_ insights: WeeklyInsights) -> String {
        var lines = [
            "## 🧭 Weekly Mood Insights (\(insights.startDate) – \(insights.endDate))",
            "",
        ]

        guard insights.totalCheckIns >= minimumCheckInsForStats else {
            lines.append("- Not enough check-ins this week yet (\(insights.totalCheckIns) so far) — keep going.")
            return lines.joined(separator: "\n")
        }

        lines.append("- Check-ins: \(insights.totalCheckIns) total (\(formatOneDecimal(insights.checkInsPerDay ?? 0)) per day)")
        if let moodAverage = insights.moodAverage, let energyAverage = insights.energyAverage {
            lines.append("- Averages: mood \(formatOneDecimal(moodAverage))/5, energy \(formatOneDecimal(energyAverage))/5")
        }
        if let bestDay = insights.bestDay, let toughestDay = insights.toughestDay {
            lines.append("- Best mood day: \(bestDay.weekdayName) (\(formatOneDecimal(bestDay.value))/5); toughest: \(toughestDay.weekdayName) (\(formatOneDecimal(toughestDay.value))/5)")
        }
        if !insights.timeOfDayAverages.isEmpty {
            let bucketText = insights.timeOfDayAverages
                .map { "\($0.bucket.rawValue.lowercased()) mood \(formatOneDecimal($0.moodAverage)), energy \(formatOneDecimal($0.energyAverage))" }
                .joined(separator: "; ")
            lines.append("- Time of day: \(bucketText)")
        }
        if let correlation = insights.sleepMoodCorrelation {
            lines.append("- Sleep and mood moved \(sleepMoodDescription(for: correlation)) this week (r=\(formatOneDecimal(correlation))).")
        }

        return lines.joined(separator: "\n")
    }

    static func shouldGenerateWeeklyInsights(lastGeneratedISOWeek: String?, currentISOWeek: String) -> Bool {
        lastGeneratedISOWeek != currentISOWeek
    }

    static func isoWeekString(for date: Date, calendar: Calendar = isoWeekCalendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    static func trailingSevenDayRange(endingOn endDate: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let endStartOfDay = calendar.startOfDay(for: endDate)
        let start = calendar.date(byAdding: .day, value: -6, to: endStartOfDay) ?? endStartOfDay
        return (start, endStartOfDay)
    }

    static func completedSevenDayRange(before date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        return trailingSevenDayRange(endingOn: dayBefore, calendar: calendar)
    }

    static func localDateString(for date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func sleepMetric(fromPayloadJSON payloadJSON: String) -> Double? {
        guard
            let data = payloadJSON.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        if let score = firstNumericValue(in: root, keyPaths: [
            ["sleep", 0, "score", "sleep_performance_percentage"],
            ["sleep", 0, "score", "sleepPerformancePercentage"],
            ["sleep", 0, "score", "sleep_score"],
            ["sleep", 0, "score", "score"],
        ]) {
            return score
        }

        if let asleepMillis = firstNumericValue(in: root, keyPaths: [
            ["sleep", 0, "score", "stage_summary", "total_light_sleep_time_milli"],
        ]).map({ light in
            light
                + (numericValue(in: root, keyPath: ["sleep", 0, "score", "stage_summary", "total_slow_wave_sleep_time_milli"]) ?? 0)
                + (numericValue(in: root, keyPath: ["sleep", 0, "score", "stage_summary", "total_rem_sleep_time_milli"]) ?? 0)
        }), asleepMillis > 0 {
            return asleepMillis / 3_600_000
        }

        if let inBedMillis = numericValue(in: root, keyPath: ["sleep", 0, "score", "stage_summary", "total_in_bed_time_milli"]),
           let awakeMillis = numericValue(in: root, keyPath: ["sleep", 0, "score", "stage_summary", "total_awake_time_milli"]) {
            let asleepMillis = inBedMillis - awakeMillis
            return asleepMillis > 0 ? asleepMillis / 3_600_000 : nil
        }

        return nil
    }

    private static let isoWeekCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    private static func average(_ values: [Int]) -> Double {
        Double(values.reduce(0, +)) / Double(values.count)
    }

    private static func makeDayAverage(from pair: (key: String, value: Double)?, calendar: Calendar) -> WeeklyInsights.DayAverage? {
        guard let pair, let date = parseLocalDate(pair.key, calendar: calendar) else { return nil }
        return WeeklyInsights.DayAverage(
            weekdayName: weekdayName(for: date, calendar: calendar),
            value: pair.value
        )
    }

    static func parseLocalDate(_ string: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private static func weekdayName(for date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func pearsonCorrelation(_ pairs: [(Double, Double)]) -> Double? {
        let count = Double(pairs.count)
        let meanX = pairs.map(\.0).reduce(0, +) / count
        let meanY = pairs.map(\.1).reduce(0, +) / count
        let numerator = pairs.reduce(0) { result, pair in
            result + (pair.0 - meanX) * (pair.1 - meanY)
        }
        let xSquares = pairs.reduce(0) { $0 + pow($1.0 - meanX, 2) }
        let ySquares = pairs.reduce(0) { $0 + pow($1.1 - meanY, 2) }
        let denominator = sqrt(xSquares * ySquares)
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func sleepMoodDescription(for correlation: Double) -> String {
        let absValue = abs(correlation)
        let direction = correlation >= 0 ? "together" : "in opposite directions"
        switch absValue {
        case 0.7...:
            return "strongly \(direction)"
        case 0.4..<0.7:
            return "moderately \(direction)"
        case 0.2..<0.4:
            return "slightly \(direction)"
        default:
            return "weakly \(direction)"
        }
    }

    private static func formatOneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func firstNumericValue(in root: Any, keyPaths: [[Any]]) -> Double? {
        for keyPath in keyPaths {
            if let value = numericValue(in: root, keyPath: keyPath) {
                return value
            }
        }
        return nil
    }

    private static func numericValue(in root: Any, keyPath: [Any]) -> Double? {
        var current: Any? = root
        for component in keyPath {
            if let key = component as? String {
                current = (current as? [String: Any])?[key]
            } else if let index = component as? Int {
                guard let array = current as? [Any], array.indices.contains(index) else { return nil }
                current = array[index]
            }
        }

        switch current {
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as Int64:
            return Double(value)
        case let value as NSNumber:
            return value.doubleValue
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }
}
