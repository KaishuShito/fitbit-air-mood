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
    @Published var isShowingActions = false
    @Published var searchText = "" {
        didSet {
            if searchText != oldValue { selectionIndex = 0 }
        }
    }
    @Published var paletteQuery = "" {
        didSet {
            if paletteQuery != oldValue { selectionIndex = 0 }
        }
    }
    @Published var selectionIndex = 0
    @Published private(set) var footerMessage: FooterMessage?

    // Set by the window controller so the "Close Window" action can reach the panel.
    var requestCloseWindow: (() -> Void)?

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

    var hasDeletableNote: Bool {
        notes.contains { $0.id != currentNoteID }
    }

    var availableActions: [QuickNoteAction] {
        QuickNoteAction.available(hasDeletableNote: hasDeletableNote)
    }

    var filteredActions: [QuickNoteAction] {
        QuickNoteAction.filtered(availableActions, query: paletteQuery)
    }

    private var activeSelectionCount: Int {
        if isShowingActions { return filteredActions.count }
        if isBrowsing { return filteredNotes.count }
        return 0
    }

    // MARK: - Lifecycle

    func prepareForDisplay() {
        reloadNotes()
        isBrowsing = false
        isShowingActions = false
        searchText = ""
        paletteQuery = ""
        selectionIndex = 0
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
        closeOverlays()
        clearFeedback()
    }

    func openNote(id: String) {
        guard id != currentNoteID else {
            closeOverlays()
            return
        }
        persistCurrent()
        guard let note = notes.first(where: { $0.id == id }) else { return }
        currentNoteID = id
        content = note.content
        closeOverlays()
        clearFeedback()
    }

    // The open note cannot delete itself — closing/switching first keeps the
    // editor and its autosave from writing a row that was just removed.
    func deleteNote(id: String) {
        guard id != currentNoteID else { return }
        try? store.deleteQuickNote(id: id)
        reloadNotes()
        if isBrowsing {
            selectionIndex = ListSelection.clamp(selectionIndex, count: filteredNotes.count)
        }
    }

    // MARK: - Overlays and selection

    func toggleBrowsing() {
        if isBrowsing {
            closeOverlays()
        } else {
            openBrowse()
        }
    }

    func openBrowse() {
        isShowingActions = false
        paletteQuery = ""
        searchText = ""
        isBrowsing = true
        selectionIndex = 0
    }

    func toggleActions() {
        if isShowingActions {
            isShowingActions = false
            paletteQuery = ""
        } else {
            openActions()
        }
    }

    func openActions() {
        isBrowsing = false
        searchText = ""
        paletteQuery = ""
        isShowingActions = true
        selectionIndex = 0
    }

    func closeOverlays() {
        isBrowsing = false
        isShowingActions = false
        searchText = ""
        paletteQuery = ""
    }

    func moveSelection(by delta: Int) {
        selectionIndex = ListSelection.move(selectionIndex, by: delta, count: activeSelectionCount)
    }

    func activateSelection() {
        if isShowingActions {
            activateSelectedAction()
        } else if isBrowsing {
            openSelectedNote()
        }
    }

    func openSelectedNote() {
        guard filteredNotes.indices.contains(selectionIndex) else { return }
        openNote(id: filteredNotes[selectionIndex].id)
    }

    func deleteSelectedNote() {
        guard isBrowsing, filteredNotes.indices.contains(selectionIndex) else { return }
        let note = filteredNotes[selectionIndex]
        guard note.id != currentNoteID else {
            showFeedback(FooterMessage(text: "The open note can't be deleted", isError: true))
            return
        }
        let deletedIndex = selectionIndex
        try? store.deleteQuickNote(id: note.id)
        reloadNotes()
        selectionIndex = ListSelection.afterDelete(
            selected: selectionIndex,
            deletedIndex: deletedIndex,
            newCount: filteredNotes.count
        )
    }

    func activateSelectedAction() {
        guard filteredActions.indices.contains(selectionIndex) else { return }
        execute(filteredActions[selectionIndex])
    }

    func execute(_ action: QuickNoteAction) {
        switch action {
        case .newNote:
            newNote()
        case .browseNotes:
            openBrowse()
        case .saveToJournal:
            closeOverlays()
            saveToJournal()
        case .deleteNote:
            // Deletion needs a chosen target, so route into the browse list.
            openBrowse()
        case .closeWindow:
            requestCloseWindow?()
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
