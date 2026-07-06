import Foundation

// Pure selection-index math shared by the browse and actions overlays. No
// wrapping: arrows stop at the ends. Empty lists resolve to index 0 so callers
// can rely on a stable value even before bounds checks.
enum ListSelection {
    static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }

    static func move(_ index: Int, by delta: Int, count: Int) -> Int {
        clamp(index + delta, count: count)
    }

    // Selection after removing the row at `deletedIndex` from a list that now
    // holds `newCount` rows. Deleting above the caret shifts it up by one;
    // deleting the caret's own row keeps the slot (the next row moves into it),
    // clamping to the new last row when the deleted row was last.
    static func afterDelete(selected: Int, deletedIndex: Int, newCount: Int) -> Int {
        guard newCount > 0 else { return 0 }
        let shifted = deletedIndex < selected ? selected - 1 : selected
        return clamp(shifted, count: newCount)
    }
}

enum QuickNoteAction: String, CaseIterable, Identifiable {
    case newNote
    case browseNotes
    case saveToJournal
    case deleteNote
    case closeWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newNote: "New Note"
        case .browseNotes: "Browse Notes"
        case .saveToJournal: "Save to Journal"
        case .deleteNote: "Delete Note"
        case .closeWindow: "Close Window"
        }
    }

    var shortcut: String {
        switch self {
        case .newNote: "⌘N"
        case .browseNotes: "⌘P"
        case .saveToJournal: "⌘⏎"
        case .deleteNote: "⌘⌫"
        case .closeWindow: "esc"
        }
    }

    var systemImage: String {
        switch self {
        case .newNote: "square.and.pencil"
        case .browseNotes: "rectangle.stack"
        case .saveToJournal: "text.append"
        case .deleteNote: "trash"
        case .closeWindow: "xmark"
        }
    }

    // Delete Note only makes sense when a note other than the open one exists,
    // so it is context-dependent; every other action is always offered.
    static func available(hasDeletableNote: Bool) -> [QuickNoteAction] {
        allCases.filter { $0 != .deleteNote || hasDeletableNote }
    }

    static func filtered(_ actions: [QuickNoteAction], query: String) -> [QuickNoteAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return actions }
        return actions.filter {
            $0.title.lowercased().contains(trimmed) || $0.shortcut.lowercased().contains(trimmed)
        }
    }
}
