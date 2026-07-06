import SwiftUI

struct QuickNoteView: View {
    @ObservedObject var model: QuickNoteModel
    @FocusState private var searchFocused: Bool
    @FocusState private var paletteFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            editorLayer

            if model.isBrowsing {
                browseOverlay
                    .transition(.opacity)
            } else if model.isShowingActions {
                actionsOverlay
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.isBrowsing)
        .animation(.easeOut(duration: 0.12), value: model.isShowingActions)
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

            Button {
                model.toggleActions()
            } label: {
                Text("⌘K")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show all actions (⌘K)")

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

    // MARK: - Browse overlay

    private var browseOverlay: some View {
        VStack(spacing: 0) {
            searchField(
                placeholder: "Search notes",
                text: $model.searchText,
                icon: "magnifyingglass",
                focus: $searchFocused
            ) {
                model.openSelectedNote()
            }

            Divider()

            if model.filteredNotes.isEmpty {
                overlayEmptyState(model.notes.isEmpty ? "No notes yet" : "No matches")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.filteredNotes.enumerated()), id: \.element.id) { index, note in
                                browseRow(note, isSelected: index == model.selectionIndex)
                                    .id(note.id)
                                Divider()
                            }
                        }
                    }
                    .onChange(of: model.selectionIndex) {
                        scrollToSelectedNote(proxy)
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            searchFocused = true
        }
    }

    private func browseRow(_ note: QuickNote, isSelected: Bool) -> some View {
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
        .background(rowBackground(isSelected: isSelected, isCurrent: isCurrent))
    }

    // MARK: - Actions palette

    private var actionsOverlay: some View {
        VStack(spacing: 0) {
            searchField(
                placeholder: "Search actions",
                text: $model.paletteQuery,
                icon: "command",
                focus: $paletteFocused
            ) {
                model.activateSelectedAction()
            }

            Divider()

            if model.filteredActions.isEmpty {
                overlayEmptyState("No matching actions")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(model.filteredActions.enumerated()), id: \.element.id) { index, action in
                            actionRow(action, isSelected: index == model.selectionIndex)
                            Divider()
                        }
                    }
                }
            }
        }
        .background(.regularMaterial)
        .onAppear {
            paletteFocused = true
        }
    }

    private func actionRow(_ action: QuickNoteAction, isSelected: Bool) -> some View {
        Button {
            model.execute(action)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: action.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(action.title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(action.shortcut)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(rowBackground(isSelected: isSelected, isCurrent: false))
    }

    // MARK: - Shared overlay pieces

    private func searchField(
        placeholder: String,
        text: Binding<String>,
        icon: String,
        focus: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .focused(focus)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func overlayEmptyState(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // Keyboard selection wins over any hover state, so the selected row carries
    // the strongest tint; the open note keeps only a faint marker underneath.
    private func rowBackground(isSelected: Bool, isCurrent: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }
        if isCurrent {
            return Color.accentColor.opacity(0.06)
        }
        return Color.clear
    }

    private func scrollToSelectedNote(_ proxy: ScrollViewProxy) {
        guard model.filteredNotes.indices.contains(model.selectionIndex) else { return }
        let id = model.filteredNotes[model.selectionIndex].id
        withAnimation(.easeOut(duration: 0.1)) {
            proxy.scrollTo(id, anchor: .center)
        }
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
