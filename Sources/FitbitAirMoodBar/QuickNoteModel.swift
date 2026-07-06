import Foundation

@MainActor
final class QuickNoteModel: ObservableObject {
    struct FooterMessage: Equatable {
        let text: String
        let isError: Bool
    }

    @Published private(set) var notes: [QuickNote] = []
    @Published var content: String = ""
    @Published var currentNoteID: String?
    @Published var isBrowsing = false
    @Published var searchText = ""
    @Published private(set) var footerMessage: FooterMessage?

    private let store: SQLiteStore
    private let journalWriter: JournalWriter
    private let journalDirectoryProvider: () -> URL?
    private let now: () -> Date

    private var autosaveTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    private static let autosaveDelay: Duration = .milliseconds(500)
    private static let feedbackDuration: Duration = .seconds(2)

    init(
        store: SQLiteStore,
        journalWriter: JournalWriter,
        journalDirectoryProvider: @escaping () -> URL?,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.journalWriter = journalWriter
        self.journalDirectoryProvider = journalDirectoryProvider
        self.now = now
    }

    var wordCount: Int {
        Self.wordCount(in: content)
    }

    var filteredNotes: [QuickNote] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.content.lowercased().contains(query) }
    }

    // MARK: - Lifecycle

    func prepareForDisplay() {
        reloadNotes()
        isBrowsing = false
        searchText = ""
        clearFeedback()

        if let mostRecent = notes.first {
            currentNoteID = mostRecent.id
            content = mostRecent.content
        } else {
            startFreshNote()
        }
    }

    func flush() {
        autosaveTask?.cancel()
        autosaveTask = nil
        persistCurrent()
    }

    // MARK: - Editing

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.persistCurrent()
        }
    }

    func newNote() {
        persistCurrent()
        startFreshNote()
        isBrowsing = false
        clearFeedback()
    }

    func openNote(id: String) {
        guard id != currentNoteID else {
            isBrowsing = false
            searchText = ""
            return
        }
        persistCurrent()
        guard let note = notes.first(where: { $0.id == id }) else { return }
        currentNoteID = id
        content = note.content
        isBrowsing = false
        searchText = ""
        clearFeedback()
    }

    // The open note cannot delete itself — closing/switching first keeps the
    // editor and its autosave from writing a row that was just removed.
    func deleteNote(id: String) {
        guard id != currentNoteID else { return }
        try? store.deleteQuickNote(id: id)
        reloadNotes()
    }

    func openFirstFilteredNote() {
        guard let first = filteredNotes.first else { return }
        openNote(id: first.id)
    }

    func toggleBrowsing() {
        isBrowsing.toggle()
        if !isBrowsing {
            searchText = ""
        }
    }

    // MARK: - Journal

    func saveToJournal() {
        persistCurrent()

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showFeedback(FooterMessage(text: "Nothing to save yet", isError: true))
            return
        }
        guard let journalDirectory = journalDirectoryProvider() else {
            showFeedback(FooterMessage(text: "No journal folder configured", isError: true))
            return
        }

        let savedAt = now()
        do {
            _ = try journalWriter.append(quickNote: content, at: savedAt, to: journalDirectory)
            if let id = currentNoteID {
                try? store.markQuickNoteJournalSaved(id: id, journalSavedAt: Self.isoString(savedAt))
                reloadNotes()
            }
            showFeedback(FooterMessage(text: "Saved to Journal \(Self.timeString(savedAt))", isError: false))
        } catch {
            showFeedback(FooterMessage(text: "Save failed: \(error.localizedDescription)", isError: true))
        }
    }

    // MARK: - Persistence helpers

    private func startFreshNote() {
        currentNoteID = UUID().uuidString
        content = ""
    }

    private func persistCurrent() {
        guard let id = currentNoteID else { return }
        let existing = notes.first { $0.id == id }
        let timestamp = Self.isoString(now())

        if existing == nil {
            // Never create a database row for a brand-new note that is still empty.
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let note = QuickNote(
                id: id,
                content: content,
                createdAt: timestamp,
                updatedAt: timestamp,
                journalSavedAt: nil
            )
            try? store.insertQuickNote(note)
        } else if existing?.content != content {
            try? store.updateQuickNoteContent(id: id, content: content, updatedAt: timestamp)
        } else {
            return
        }
        reloadNotes()
    }

    private func reloadNotes() {
        notes = (try? store.quickNotes()) ?? []
    }

    private func showFeedback(_ message: FooterMessage) {
        footerMessage = message
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: Self.feedbackDuration)
            guard !Task.isCancelled else { return }
            self?.footerMessage = nil
        }
    }

    private func clearFeedback() {
        feedbackTask?.cancel()
        feedbackTask = nil
        footerMessage = nil
    }

    nonisolated static func wordCount(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
