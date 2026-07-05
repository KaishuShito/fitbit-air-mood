import Foundation

struct JournalWriter {
    func append(checkIn: MoodCheckIn, to journalDirectory: URL) throws -> URL {
        let entry = render(checkIn: checkIn)
        return try append(section: entry, localDateString: checkIn.localDateString, createdAt: checkIn.iso8601String, to: journalDirectory)
    }

    func append(weeklyInsights markdown: String, for date: Date, to journalDirectory: URL) throws -> URL {
        let localDateString = Self.localDateString(for: date)
        let createdAt = Self.iso8601String(for: date)
        return try append(section: markdown, localDateString: localDateString, createdAt: createdAt, to: journalDirectory)
    }

    private func append(section: String, localDateString: String, createdAt: String, to journalDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: journalDirectory, withIntermediateDirectories: true)

        let fileURL = journalDirectory.appendingPathComponent("\(localDateString).md")
        let existingText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        var text = existingText

        if text.isEmpty {
            text = newFileHeader(localDateString: localDateString, createdAt: createdAt)
        }

        if !text.hasSuffix("\n") {
            text.append("\n")
        }
        text.append("\n")
        text.append(section)
        text.append("\n")

        try text.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func newFileHeader(localDateString: String, createdAt: String) -> String {
        let dateUnder = localDateString.replacingOccurrences(of: "-", with: "_")
        return """
        ---
        title: "\(dateUnder)"
        type: journal
        date: \(localDateString)
        created: \(createdAt)
        tags: [journal]
        ---
        # \(dateUnder)
        """
    }

    private func render(checkIn: MoodCheckIn) -> String {
        var lines = [
            "## Mood Check-In - \(checkIn.localTimestampString)",
            "",
            "- Mood (valence): \(checkIn.mood.emoji) \(checkIn.mood.rawValue)/5 \(checkIn.mood.label)",
            "- Energy (arousal): \(checkIn.energy.emoji) \(checkIn.energy.rawValue)/5 \(checkIn.energy.label)",
        ]

        if !checkIn.notes.isEmpty {
            lines.append("")
            lines.append("**Notes**")
            lines.append(checkIn.notes)
        }

        return lines.joined(separator: "\n")
    }

    private static func localDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func iso8601String(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}
