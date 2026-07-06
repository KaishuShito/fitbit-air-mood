import SwiftUI

enum CheckInViewMode {
    case window
    case panel
}

struct CheckInView: View {
    @ObservedObject var appState: AppState
    let mode: CheckInViewMode
    let onDismiss: (() -> Void)?
    let panelTopInset: CGFloat
    let panelWidth: CGFloat

    init(
        appState: AppState,
        mode: CheckInViewMode = .window,
        onDismiss: (() -> Void)? = nil,
        panelTopInset: CGFloat = 0,
        panelWidth: CGFloat = 360
    ) {
        self.appState = appState
        self.mode = mode
        self.onDismiss = onDismiss
        self.panelTopInset = panelTopInset
        self.panelWidth = panelWidth
    }

    @ViewBuilder
    var body: some View {
        switch mode {
        case .window:
            windowBody
        case .panel:
            panelBody
        }
    }

    private var windowBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Fitbit Air Mood Check-In")
                .font(.headline)

            Text("Save mood snapshots, sync Fitbit data, and keep a small local SQLite record.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            scaleSection(
                title: "Mood",
                subtitle: "Valence",
                selection: appState.draft.mood,
                labels: MoodLevel.allCases.map { ($0.id, $0.emoji, $0.label, $0.accessibilityLabel) }
            ) { level in
                appState.draft.mood = MoodLevel(rawValue: level) ?? .neutral
            }

            scaleSection(
                title: "Energy",
                subtitle: "Arousal",
                selection: appState.draft.energy,
                labels: EnergyLevel.allCases.map { ($0.id, $0.emoji, $0.label, $0.accessibilityLabel) }
            ) { level in
                appState.draft.energy = EnergyLevel(rawValue: level) ?? .steady
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.subheadline.weight(.semibold))
                NotesTextView(text: $appState.draft.notes)
                    .frame(minHeight: 80, maxHeight: 100)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fitbit")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(appState.isSyncingFitbit ? "Syncing..." : "Sync Now") {
                        appState.syncFitbitNow()
                    }
                    .disabled(appState.isSyncingFitbit)
                    .accessibilityLabel("Sync Fitbit Now")
                }

                if let message = appState.fitbitSyncMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Fitbit sync failed") ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Journal") {
                    Text(appState.journalDirectoryDisplay)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Database") {
                    Text(appState.databasePathDisplay)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let message = appState.saveMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            if let message = appState.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Choose Journal Folder…") {
                    appState.chooseJournalDirectory()
                }
                .accessibilityLabel("Choose Journal Folder")

                Button("Reset") {
                    appState.resetJournalDirectoryToDetectedDefault()
                }
                .accessibilityLabel("Reset Journal Folder")
            }

            Toggle("Hourly reminder on the hour", isOn: $appState.reminderEnabled)
                .accessibilityLabel("Hourly reminder on the hour")

            Toggle("Quiet hourly reminders", isOn: $appState.quietHourlyReminders)
                .accessibilityLabel("Quiet hourly reminders")

            Text(appState.quietHourlyReminders ? "Hourly checks post a notification only. Click it or use the menu bar when you want to answer." : "Hourly checks open the quick panel and post a notification.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message = appState.notificationStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { appState.launchAtLoginEnabled },
                    set: { appState.setLaunchAtLogin($0) }
                )
            )

            if let message = appState.launchAtLoginStatusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Quit") {
                    appState.quitApplication()
                }
                .accessibilityLabel("Quit")

                Button("Restart") {
                    appState.restartApplication()
                }
                .accessibilityLabel("Restart")

                Spacer()
            }

            HStack(spacing: 8) {
                Button("Open Today's Journal") {
                    appState.openTodayJournal()
                }
                .accessibilityLabel("Open Today's Journal")

                Button("Show DB") {
                    appState.openDatabaseFolder()
                }
                .accessibilityLabel("Show Database")

                Button("Login Items") {
                    appState.openLoginItemsSettings()
                }
                .accessibilityLabel("Open Login Items Settings")

                Button("Test Reminder") {
                    appState.triggerReminderNow()
                }
                .accessibilityLabel("Test Reminder")

                Spacer()
            }

            HStack(spacing: 8) {
                Spacer()
                Button(appState.isSaving ? "Saving..." : "Save Check-In") {
                    appState.saveCheckIn()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isSaving)
                .accessibilityLabel("Save Check-In")
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Quick Check-In")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Mood \(appState.draft.mood.rawValue) / Energy \(appState.draft.energy.rawValue)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Button {
                    onDismiss?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .background(Color.white.opacity(0.08), in: Circle())
                .help("Skip Check-In")
                .accessibilityLabel("Skip Check-In")
            }

            compactScaleSection(
                title: "Mood",
                selection: appState.draft.mood,
                isActive: appState.panelActiveRow == .mood,
                labels: MoodLevel.allCases.map { ($0.id, $0.emoji, $0.label, $0.accessibilityLabel) }
            ) { level in
                appState.draft.mood = MoodLevel(rawValue: level) ?? .neutral
                appState.panelActiveRow = .energy
            }

            compactScaleSection(
                title: "Energy",
                selection: appState.draft.energy,
                isActive: appState.panelActiveRow == .energy,
                labels: EnergyLevel.allCases.map { ($0.id, $0.emoji, $0.label, $0.accessibilityLabel) }
            ) { level in
                appState.draft.energy = EnergyLevel(rawValue: level) ?? .steady
                focusNotesAfterLayout()
            }

            panelNotesSection

            if let message = panelStatusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(panelStatusIsError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(message)
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    appState.openMainWindow()
                } label: {
                    Image(systemName: "macwindow")
                        .frame(width: 28, height: 28)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.78))
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .help("Open Full Window")
                .accessibilityLabel("Open Full Window")

                Spacer()

                Button {
                    appState.saveCheckIn(fromPanel: true)
                } label: {
                    Label(appState.isSaving ? "Saving" : "Save", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(minWidth: 82, minHeight: 30)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isSaving)
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Color.accentColor.opacity(appState.isSaving ? 0.45 : 0.95), in: Capsule())
                .accessibilityLabel("Save Check-In")
            }

            Text(appState.isPanelNotesFocused ? "⌘⏎ save · esc back to scales" : "1–5 select · ⇥ row · N notes · ⏎ save · esc close")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, panelTopInset > 0 ? panelTopInset + 10 : 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
        .frame(width: panelWidth, height: panelHeight, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.34), radius: 18, x: 0, y: 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var panelNotesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            NotesTextView(text: $appState.draft.notes, isDarkHUD: true, onFocusChange: { focused in
                appState.isPanelNotesFocused = focused
            })
                .frame(height: 50)
                .padding(1)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }

    private var panelHeight: CGFloat {
        420 + panelTopInset
    }

    private var panelStatusMessage: String? {
        if let errorMessage = appState.errorMessage {
            return errorMessage
        }

        return appState.saveMessage
    }

    private var panelStatusIsError: Bool {
        appState.errorMessage != nil
    }

    private func focusNotesAfterLayout() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .fitbitAirMoodBarFocusNotes, object: nil)
        }
    }

    private func scaleSection<T: RawRepresentable>(
        title: String,
        subtitle: String,
        selection: T,
        labels: [(Int, String, String, String)],
        onSelect: @escaping (Int) -> Void
    ) -> some View where T.RawValue == Int {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                ForEach(labels, id: \.0) { item in
                    Button {
                        onSelect(item.0)
                    } label: {
                        VStack(spacing: 4) {
                            Text(item.1)
                                .font(.title3)
                            Text("\(item.0)")
                                .font(.caption2.monospacedDigit())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selection.rawValue == item.0 ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .help(item.3)
                }
            }

            Text(labels.first(where: { $0.0 == selection.rawValue })?.2 ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func compactScaleSection<T: RawRepresentable>(
        title: String,
        selection: T,
        isActive: Bool,
        labels: [(Int, String, String, String)],
        onSelect: @escaping (Int) -> Void
    ) -> some View where T.RawValue == Int {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(isActive ? 0.72 : 0))
                    .frame(width: 9)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(isActive ? 0.94 : 0.76))

                Spacer()

                Text(selectedLabel(selection: selection, labels: labels))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.46))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                ForEach(labels, id: \.0) { item in
                    let isSelected = selection.rawValue == item.0
                    Button {
                        onSelect(item.0)
                    } label: {
                        VStack(spacing: 2) {
                            Text(item.1)
                                .font(.title3)
                            Text("\(item.0)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.white.opacity(isSelected ? 0.92 : 0.55))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            isSelected ? Color.accentColor.opacity(0.74) : Color.white.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Color.white.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(item.3)
                    .accessibilityValue("\(item.0) of 5")
                    .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
                }
            }
        }
        .padding(6)
        .background(Color.white.opacity(isActive ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(isActive ? 0.16 : 0), lineWidth: 1)
        }
    }

    private func selectedLabel<T: RawRepresentable>(
        selection: T,
        labels: [(Int, String, String, String)]
    ) -> String where T.RawValue == Int {
        labels.first(where: { $0.0 == selection.rawValue })?.2 ?? ""
    }
}
