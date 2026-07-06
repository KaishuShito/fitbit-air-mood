import Charts
import SwiftUI

extension Notification.Name {
    static let fitbitAirMoodBarRefreshInsights = Notification.Name("fitbitAirMoodBarRefreshInsights")
}

@MainActor
struct InsightsView: View {
    @ObservedObject var appState: AppState
    @State private var rangeDays = 30
    @State private var model: InsightsChartModel?

    private let rangeOptions = [7, 30, 90]
    private let moodSeries = "Mood"
    private let energySeries = "Energy"
    private var seriesColors: KeyValuePairs<String, Color> {
        ["Mood": .blue, "Energy": .orange]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let model, model.hasData {
                    moodEnergySection(model)
                    Divider()
                    timeOfDaySection(model)
                    Divider()
                    sleepMoodSection(model)
                } else {
                    emptyState
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 480)
        .onAppear(perform: reload)
        .onChange(of: rangeDays) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .fitbitAirMoodBarRefreshInsights)) { _ in
            reload()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mood Insights")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Picker("Range", selection: $rangeDays) {
                ForEach(rangeOptions, id: \.self) { days in
                    Text("\(days) days").tag(days)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }

    private func moodEnergySection(_ model: InsightsChartModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood & Energy")
                .font(.headline)
            Text("Daily averages, 1–5")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(model.dailyAverages) { day in
                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Score", day.mood),
                        series: .value("Series", moodSeries)
                    )
                    .foregroundStyle(by: .value("Series", moodSeries))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", day.date),
                        y: .value("Score", day.mood)
                    )
                    .foregroundStyle(by: .value("Series", moodSeries))

                    LineMark(
                        x: .value("Date", day.date),
                        y: .value("Score", day.energy),
                        series: .value("Series", energySeries)
                    )
                    .foregroundStyle(by: .value("Series", energySeries))
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", day.date),
                        y: .value("Score", day.energy)
                    )
                    .foregroundStyle(by: .value("Series", energySeries))
                }
            }
            .chartForegroundStyleScale(seriesColors)
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(values: [1, 2, 3, 4, 5])
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 220)
        }
    }

    private func timeOfDaySection(_ model: InsightsChartModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time of day")
                .font(.headline)
            Text("Average mood and energy by part of day")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Chart {
                ForEach(model.bucketAverages) { bucket in
                    BarMark(
                        x: .value("Time", bucket.bucket.rawValue),
                        y: .value("Score", bucket.mood)
                    )
                    .foregroundStyle(by: .value("Series", moodSeries))
                    .position(by: .value("Series", moodSeries))

                    BarMark(
                        x: .value("Time", bucket.bucket.rawValue),
                        y: .value("Score", bucket.energy)
                    )
                    .foregroundStyle(by: .value("Series", energySeries))
                    .position(by: .value("Series", energySeries))
                }
            }
            .chartForegroundStyleScale(seriesColors)
            .chartXScale(domain: model.bucketAverages.map(\.bucket.rawValue))
            .chartYScale(domain: 1...5)
            .chartYAxis {
                AxisMarks(values: [1, 2, 3, 4, 5])
            }
            .frame(height: 200)
        }
    }

    private func sleepMoodSection(_ model: InsightsChartModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep × Mood")
                .font(.headline)

            if model.hasEnoughSleepPairs {
                Text(correlationSubtitle(model))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Chart(model.sleepMoodPoints) { point in
                    PointMark(
                        x: .value("Sleep", point.sleep),
                        y: .value("Mood", point.mood)
                    )
                    .foregroundStyle(.blue)
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5])
                }
                .frame(height: 220)
            } else {
                Text("Not enough paired sleep data yet — keep checking in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No check-ins in this range yet")
                .font(.headline)
            Text("Save a few mood check-ins and your trends will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private func correlationSubtitle(_ model: InsightsChartModel) -> String {
        let count = model.sleepMoodPoints.count
        if let correlation = model.correlation {
            return String(format: "r = %.2f · %d nights", correlation, count)
        }
        return "\(count) nights"
    }

    private func reload() {
        model = appState.insightsChartData(days: rangeDays)
    }
}
