import Foundation
import SQLite3

final class SQLiteStore {
    private var db: OpaquePointer?

    init(databaseURL: URL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            throw SQLiteError(message: "Failed to open database at \(databaseURL.path)")
        }

        try execute("PRAGMA auto_vacuum=INCREMENTAL;")
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=ON;")
        try execute("""
        CREATE TABLE IF NOT EXISTS mood_checkins (
            id TEXT PRIMARY KEY,
            recorded_at TEXT NOT NULL,
            local_date TEXT NOT NULL,
            mood_value INTEGER NOT NULL,
            mood_label TEXT NOT NULL,
            energy_value INTEGER NOT NULL,
            energy_label TEXT NOT NULL,
            notes TEXT NOT NULL,
            journal_file_path TEXT NOT NULL,
            fitbit_snapshot_date TEXT NULL,
            fitbit_snapshot_age_minutes INTEGER NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try addColumnIfNeeded(
            tableName: "mood_checkins",
            columnName: "fitbit_snapshot_date",
            definition: "fitbit_snapshot_date TEXT NULL"
        )
        try addColumnIfNeeded(
            tableName: "mood_checkins",
            columnName: "fitbit_snapshot_age_minutes",
            definition: "fitbit_snapshot_age_minutes INTEGER NULL"
        )
        try execute("""
        CREATE TABLE IF NOT EXISTS fitbit_daily_snapshots (
            local_date TEXT PRIMARY KEY,
            recorded_at TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            payload_bytes INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS quick_notes (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            journal_saved_at TEXT NULL
        );
        """)
        try compact()
    }

    deinit {
        sqlite3_close(db)
    }

    func insert(checkIn: MoodCheckIn, journalFileURL: URL, fitbitSnapshotLink: FitbitSnapshotLink? = nil) throws {
        let sql = """
        INSERT INTO mood_checkins (
            id, recorded_at, local_date, mood_value, mood_label,
            energy_value, energy_label, notes, journal_file_path,
            fitbit_snapshot_date, fitbit_snapshot_age_minutes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, checkIn.id.uuidString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, checkIn.iso8601String, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, checkIn.localDateString, -1, transientDestructor)
        sqlite3_bind_int(statement, 4, Int32(checkIn.mood.rawValue))
        sqlite3_bind_text(statement, 5, checkIn.mood.label, -1, transientDestructor)
        sqlite3_bind_int(statement, 6, Int32(checkIn.energy.rawValue))
        sqlite3_bind_text(statement, 7, checkIn.energy.label, -1, transientDestructor)
        sqlite3_bind_text(statement, 8, checkIn.notes, -1, transientDestructor)
        sqlite3_bind_text(statement, 9, journalFileURL.path, -1, transientDestructor)
        if let fitbitSnapshotLink {
            sqlite3_bind_text(statement, 10, fitbitSnapshotLink.localDateString, -1, transientDestructor)
            sqlite3_bind_int(statement, 11, Int32(fitbitSnapshotLink.ageMinutes))
        } else {
            sqlite3_bind_null(statement, 10)
            sqlite3_bind_null(statement, 11)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastSQLiteError()
        }
    }

    func upsertFitbitSnapshot(_ snapshot: FitbitDailySnapshot) throws {
        let sql = """
        INSERT INTO fitbit_daily_snapshots (
            local_date, recorded_at, payload_json, payload_bytes
        ) VALUES (?, ?, ?, ?)
        ON CONFLICT(local_date) DO UPDATE SET
            recorded_at = excluded.recorded_at,
            payload_json = excluded.payload_json,
            payload_bytes = excluded.payload_bytes,
            updated_at = CURRENT_TIMESTAMP;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, snapshot.localDateString, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, snapshot.iso8601String, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, snapshot.payloadJSON, -1, transientDestructor)
        sqlite3_bind_int(statement, 4, Int32(snapshot.payloadBytes))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastSQLiteError()
        }
    }

    func fitbitSnapshotCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM fitbit_daily_snapshots;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw lastSQLiteError()
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    func currentFitbitSnapshotLink(for checkIn: MoodCheckIn, now: Date = Date()) throws -> FitbitSnapshotLink? {
        let sql = "SELECT local_date, recorded_at FROM fitbit_daily_snapshots WHERE local_date = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, checkIn.localDateString, -1, transientDestructor)

        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE {
                return nil
            }
            throw lastSQLiteError()
        }

        guard
            let dateCString = sqlite3_column_text(statement, 0),
            let recordedAtCString = sqlite3_column_text(statement, 1)
        else {
            return nil
        }

        let localDateString = String(cString: dateCString)
        let recordedAtString = String(cString: recordedAtCString)
        guard let snapshotRecordedAt = Self.parseDate(recordedAtString) else {
            throw SQLiteError(message: "Could not parse Fitbit snapshot recorded_at: \(recordedAtString)")
        }

        let ageMinutes = max(0, Int(now.timeIntervalSince(snapshotRecordedAt) / 60))
        return FitbitSnapshotLink(localDateString: localDateString, ageMinutes: ageMinutes)
    }

    func latestCheckInSummary(localDate: String) throws -> (recordedAt: Date, moodValue: Int, energyValue: Int)? {
        let sql = """
        SELECT recorded_at, mood_value, energy_value
        FROM mood_checkins
        WHERE local_date = ?
        ORDER BY recorded_at DESC
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, localDate, -1, transientDestructor)

        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE {
                return nil
            }
            throw lastSQLiteError()
        }

        guard let recordedAtCString = sqlite3_column_text(statement, 0) else {
            return nil
        }

        let recordedAtString = String(cString: recordedAtCString)
        guard let recordedAt = Self.parseDate(recordedAtString) else {
            throw SQLiteError(message: "Could not parse mood check-in recorded_at: \(recordedAtString)")
        }

        return (
            recordedAt: recordedAt,
            moodValue: Int(sqlite3_column_int(statement, 1)),
            energyValue: Int(sqlite3_column_int(statement, 2))
        )
    }

    func checkIns(from startLocalDate: String, through endLocalDate: String) throws -> [InsightCheckIn] {
        let sql = """
        SELECT recorded_at, local_date, mood_value, energy_value
        FROM mood_checkins
        WHERE local_date >= ? AND local_date <= ?
        ORDER BY recorded_at ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, startLocalDate, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, endLocalDate, -1, transientDestructor)

        var checkIns: [InsightCheckIn] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return checkIns
            }
            guard result == SQLITE_ROW else {
                throw lastSQLiteError()
            }
            guard
                let recordedAtCString = sqlite3_column_text(statement, 0),
                let localDateCString = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            let recordedAtString = String(cString: recordedAtCString)
            guard let recordedAt = Self.parseDate(recordedAtString) else {
                throw SQLiteError(message: "Could not parse mood check-in recorded_at: \(recordedAtString)")
            }

            checkIns.append(InsightCheckIn(
                recordedAt: recordedAt,
                localDate: String(cString: localDateCString),
                moodValue: Int(sqlite3_column_int(statement, 2)),
                energyValue: Int(sqlite3_column_int(statement, 3))
            ))
        }
    }

    func fitbitSnapshots(from startLocalDate: String, through endLocalDate: String) throws -> [InsightFitbitSnapshot] {
        let sql = """
        SELECT local_date, payload_json
        FROM fitbit_daily_snapshots
        WHERE local_date >= ? AND local_date <= ?
        ORDER BY local_date ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, startLocalDate, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, endLocalDate, -1, transientDestructor)

        var snapshots: [InsightFitbitSnapshot] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return snapshots
            }
            guard result == SQLITE_ROW else {
                throw lastSQLiteError()
            }
            guard
                let localDateCString = sqlite3_column_text(statement, 0),
                let payloadCString = sqlite3_column_text(statement, 1)
            else {
                continue
            }

            snapshots.append(InsightFitbitSnapshot(
                localDate: String(cString: localDateCString),
                payloadJSON: String(cString: payloadCString)
            ))
        }
    }

    func savedFitbitSnapshotLink(checkInID: UUID) throws -> FitbitSnapshotLink? {
        let sql = "SELECT fitbit_snapshot_date, fitbit_snapshot_age_minutes FROM mood_checkins WHERE id = ? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, checkInID.uuidString, -1, transientDestructor)

        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else {
            if result == SQLITE_DONE {
                return nil
            }
            throw lastSQLiteError()
        }

        guard sqlite3_column_type(statement, 0) != SQLITE_NULL else {
            return nil
        }

        guard let dateCString = sqlite3_column_text(statement, 0) else {
            return nil
        }

        return FitbitSnapshotLink(
            localDateString: String(cString: dateCString),
            ageMinutes: Int(sqlite3_column_int(statement, 1))
        )
    }

    func checkInCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM mood_checkins;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw lastSQLiteError()
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    func insertQuickNote(_ note: QuickNote) throws {
        let sql = """
        INSERT INTO quick_notes (id, content, created_at, updated_at, journal_saved_at)
        VALUES (?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, note.id, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, note.content, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, note.createdAt, -1, transientDestructor)
        sqlite3_bind_text(statement, 4, note.updatedAt, -1, transientDestructor)
        if let journalSavedAt = note.journalSavedAt {
            sqlite3_bind_text(statement, 5, journalSavedAt, -1, transientDestructor)
        } else {
            sqlite3_bind_null(statement, 5)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastSQLiteError()
        }
    }

    func updateQuickNoteContent(id: String, content: String, updatedAt: String) throws {
        let sql = "UPDATE quick_notes SET content = ?, updated_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, content, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, updatedAt, -1, transientDestructor)
        sqlite3_bind_text(statement, 3, id, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastSQLiteError()
        }
    }

    func markQuickNoteJournalSaved(id: String, journalSavedAt: String) throws {
        let sql = "UPDATE quick_notes SET journal_saved_at = ? WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, journalSavedAt, -1, transientDestructor)
        sqlite3_bind_text(statement, 2, id, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastSQLiteError()
        }
    }

    func deleteQuickNote(id: String) throws {
        let sql = "DELETE FROM quick_notes WHERE id = ?;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, transientDestructor)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw lastSQLiteError()
        }
    }

    func quickNotes() throws -> [QuickNote] {
        let sql = """
        SELECT id, content, created_at, updated_at, journal_saved_at
        FROM quick_notes
        ORDER BY updated_at DESC, created_at DESC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        var notes: [QuickNote] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return notes
            }
            guard result == SQLITE_ROW else {
                throw lastSQLiteError()
            }
            guard
                let idCString = sqlite3_column_text(statement, 0),
                let contentCString = sqlite3_column_text(statement, 1),
                let createdAtCString = sqlite3_column_text(statement, 2),
                let updatedAtCString = sqlite3_column_text(statement, 3)
            else {
                continue
            }

            let journalSavedAt = sqlite3_column_text(statement, 4).map { String(cString: $0) }
            notes.append(QuickNote(
                id: String(cString: idCString),
                content: String(cString: contentCString),
                createdAt: String(cString: createdAtCString),
                updatedAt: String(cString: updatedAtCString),
                journalSavedAt: journalSavedAt
            ))
        }
    }

    func mostRecentlyUpdatedQuickNote() throws -> QuickNote? {
        try quickNotes().first
    }

    func quickNoteCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM quick_notes;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw lastSQLiteError()
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
    }

    private func addColumnIfNeeded(tableName: String, columnName: String, definition: String) throws {
        guard try !hasColumn(tableName: tableName, columnName: columnName) else { return }
        try execute("ALTER TABLE \(tableName) ADD COLUMN \(definition);")
    }

    private func hasColumn(tableName: String, columnName: String) throws -> Bool {
        let sql = "PRAGMA table_info(\(tableName));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw lastSQLiteError()
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let nameCString = sqlite3_column_text(statement, 1) else { continue }
            if String(cString: nameCString) == columnName {
                return true
            }
        }

        return false
    }

    private func compact() throws {
        try execute("PRAGMA incremental_vacuum(128);")
        try execute("PRAGMA optimize;")
    }

    private func lastSQLiteError() -> SQLiteError {
        let message = sqlite3_errmsg(db).map { String(cString: $0) } ?? "Unknown SQLite error"
        return SQLiteError(message: message)
    }

    private static func parseDate(_ string: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withFractionalSeconds.timeZone = .current
        if let date = withFractionalSeconds.date(from: string) {
            return date
        }

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        withoutFractionalSeconds.timeZone = .current
        return withoutFractionalSeconds.date(from: string)
    }
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct FitbitSnapshotLink: Equatable {
    let localDateString: String
    let ageMinutes: Int
}

struct QuickNote: Identifiable, Equatable {
    let id: String
    var content: String
    let createdAt: String
    var updatedAt: String
    var journalSavedAt: String?

    var displayTitle: String {
        Self.displayTitle(for: content)
    }

    // The first non-blank line is the note's title (Raycast convention); a note
    // that is empty or all whitespace falls back to "Untitled".
    static func displayTitle(for content: String) -> String {
        let firstNonBlankLine = content
            .split(whereSeparator: \.isNewline)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let firstNonBlankLine else { return "Untitled" }
        return firstNonBlankLine.trimmingCharacters(in: .whitespaces)
    }
}

struct SQLiteError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
