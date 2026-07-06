import SwiftUI

struct QuickNoteView: View {
    @ObservedObject var model: QuickNoteModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            editorLayer

            if model.isBrowsing {
                browseOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.isBrowsing)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var editorLayer: some View {
        VStack(spacing: 0) {
            NotesTextView(
                text: $model.content,
                placeholder: "Start writing…",
                fontSize: 15,
                contentInset: 16,
                focusNotification: .fitbitAirMoodBarFocusQuickNote
            )
            .padding(.top, 22)
            .onChange(of: model.content) {
                model.scheduleAutosave()
            }

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                model.toggleBrowsing()
            } label: {
                Label(noteSwitcherLabel, systemImage: "rectangle.stack")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Browse notes (⌘P)")

            Spacer(minLength: 8)

            Text(centerText)
                .font(.caption)
                .foregroundStyle(footerIsError ? Color.red : .secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                model.saveToJournal()
            } label: {
                Text("Save to Journal ⌘⏎")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Append this note to today's journal")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var noteSwitcherLabel: String {
        let count = model.notes.count
        if count <= 1 {
            return "Notes"
        }
        return "\(count) notes"
    }

    private var centerText: String {
        if let message = model.footerMessage {
            return message.text
        }
        let count = model.wordCount
        return count == 1 ? "1 word" : "\(count) words"
    }

    private var footerIsError: Bool {
        model.footerMessage?.isError ?? false
    }

    private var browseOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notes", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        model.openFirstFilteredNote()
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if model.filteredNotes.isEmpty {
                Spacer()
                Text(model.notes.isEmpty ? "No notes yet" : "No matches")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.filteredNotes) { note in
                            browseRow(note)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            searchFocused = true
        }
    }

    private func browseRow(_ note: QuickNote) -> some View {
        let isCurrent = note.id == model.currentNoteID
        return HStack(alignment: .top, spacing: 10) {
            Button {
                model.openNote(id: note.id)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(Self.relativeTime(from: note.updatedAt))
                        Text("·")
                        Text("\(note.content.count) chars")
                        if isCurrent {
                            Text("·")
                            Text("open")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.deleteNote(id: note.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(isCurrent)
            .opacity(isCurrent ? 0.25 : 1)
            .help(isCurrent ? "The open note can't be deleted" : "Delete note")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isCurrent ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private static func relativeTime(from isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: isoString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: isoString)
        }
        guard let date else { return "" }
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated
        return relative.localizedString(for: date, relativeTo: Date())
    }
}
