import Foundation

enum MoodLevel: Int, CaseIterable, Identifiable {
    case veryLow = 1
    case low = 2
    case neutral = 3
    case good = 4
    case great = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .veryLow: "😞"
        case .low: "🙁"
        case .neutral: "😐"
        case .good: "🙂"
        case .great: "😄"
        }
    }

    var label: String {
        switch self {
        case .veryLow: "Very Low"
        case .low: "Low"
        case .neutral: "Neutral"
        case .good: "Good"
        case .great: "Great"
        }
    }

    var accessibilityLabel: String {
        "\(label) mood"
    }
}

enum EnergyLevel: Int, CaseIterable, Identifiable {
    case drained = 1
    case low = 2
    case steady = 3
    case high = 4
    case veryHigh = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .drained: "🪫"
        case .low: "🌥️"
        case .steady: "⚡️"
        case .high: "🔆"
        case .veryHigh: "☀️"
        }
    }

    var label: String {
        switch self {
        case .drained: "Drained"
        case .low: "Low"
        case .steady: "Steady"
        case .high: "High"
        case .veryHigh: "Very High"
        }
    }

    var accessibilityLabel: String {
        "\(label) energy"
    }
}

struct MoodCheckIn: Identifiable {
    let id: UUID
    let recordedAt: Date
    let mood: MoodLevel
    let energy: EnergyLevel
    let notes: String

    init(id: UUID = UUID(), recordedAt: Date = Date(), mood: MoodLevel, energy: EnergyLevel, notes: String) {
        self.id = id
        self.recordedAt = recordedAt
        self.mood = mood
        self.energy = energy
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var localDateString: String {
        Self.makeLocalDateFormatter().string(from: recordedAt)
    }

    var localTimestampString: String {
        Self.makeLocalTimestampFormatter().string(from: recordedAt)
    }

    var iso8601String: String {
        Self.makeISOFormatter().string(from: recordedAt)
    }

    private static func makeLocalDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func makeLocalTimestampFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }

    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }
}

struct MoodDraft {
    var mood: MoodLevel = .neutral
    var energy: EnergyLevel = .steady
    var notes: String = ""

    mutating func reset() {
        mood = .neutral
        energy = .steady
        notes = ""
    }
}
