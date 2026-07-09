import SwiftUI

struct TasksView: View {
    enum Mode {
        case panel
        case expanded
    }

    @ObservedObject var model: TasksModel
    let mode: Mode
    let onDismiss: () -> Void
    let onExpand: (() -> Void)?
    let panelTopInset: CGFloat
    let panelWidth: CGFloat

    init(
        model: TasksModel,
        mode: Mode,
        onDismiss: @escaping () -> Void,
        onExpand: (() -> Void)? = nil,
        panelTopInset: CGFloat = 0,
        panelWidth: CGFloat = 360
    ) {
        self.model = model
        self.mode = mode
        self.onDismiss = onDismiss
        self.onExpand = onExpand
        self.panelTopInset = panelTopInset
        self.panelWidth = panelWidth
    }

    @ViewBuilder
    var body: some View {
        switch mode {
        case .panel:
            panelBody
        case .expanded:
            expandedBody
        }
    }

    // MARK: - Panel

    static let basePanelHeight: CGFloat = 470

    private var panelBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                Text("Tasks")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    onExpand?()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .background(Color.white.opacity(0.08), in: Circle())
                .help("Open as Window (⌘O)")
                .accessibilityLabel("Open Tasks Window")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .background(Color.white.opacity(0.08), in: Circle())
                .help("Close (esc)")
                .accessibilityLabel("Close Tasks")
            }

            editor

            footerHint
        }
        .padding(.top, panelTopInset > 0 ? panelTopInset + 10 : 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .frame(width: panelWidth, height: Self.basePanelHeight + panelTopInset, alignment: .top)
        .background {
            Self.panelShape
                .fill(Color.black)
                .shadow(color: Color.black.opacity(0.34), radius: 18, x: 0, y: 10)
        }
        .clipShape(Self.panelShape)
        .environment(\.colorScheme, .dark)
    }

    // Square top corners: the panel reads as sliding out from the notch/menu bar.
    private static var panelShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 30,
            bottomTrailingRadius: 30,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    // MARK: - Expanded

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                Text("Tasks")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Button {
                    onExpand?()
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .background(Color.white.opacity(0.08), in: Circle())
                .help("Back to Compact Panel (⌘O)")
                .accessibilityLabel("Back to Compact Tasks Panel")

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 24, height: 24)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .background(Color.white.opacity(0.08), in: Circle())
                .help("Close (esc)")
                .accessibilityLabel("Close Tasks")
            }

            editor

            footerHint
        }
        .padding(14)
        .frame(minWidth: 420, minHeight: 360)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Shared pieces

    private var editor: some View {
        TasksTextView(text: $model.content)
            .onChange(of: model.content) {
                model.scheduleAutosave()
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            }
    }

    private var footerHint: some View {
        HStack(spacing: 0) {
            if let message = model.footerMessage {
                Text(message.text)
                    .foregroundStyle(message.isError ? Color.red.opacity(0.9) : Color.green.opacity(0.9))
            } else {
                Text(mode == .panel ? "⌘L check · ⌘O expand · ⌘S save · esc close" : "⌘L check · ⌘O shrink · ⌘S save · esc close")
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .lineLimit(1)
    }
}
