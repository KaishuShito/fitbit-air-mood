import AppKit
import SwiftUI
import os.log

private final class TasksPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class TasksPanelController: NSWindowController, NSWindowDelegate {
    private static let fallbackPanelWidth: CGFloat = 380
    private let model: TasksModel
    private let hosting: NSHostingController<TasksView>
    private let panel: TasksPanel
    private var keyMonitor: Any?

    // ⌘O grows the same panel in place instead of opening a separate window:
    // a second window could not reliably take key input while the app stays
    // inactive (macOS 26 cooperative activation), whereas the already-key
    // panel keeps its key status through a frame change.
    private var isExpanded = false

    init(model: TasksModel) {
        self.model = model
        self.hosting = NSHostingController(
            rootView: TasksView(model: model, mode: .panel, onDismiss: {})
        )
        // .nonactivatingPanel keeps the frontmost app (including fullscreen
        // Chrome/Obsidian spaces) active while the panel takes key input —
        // the Spotlight/Raycast pattern. Activating the app instead would
        // switch spaces and hide the panel on fullscreen displays.
        panel = TasksPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: Self.fallbackPanelWidth, height: TasksView.basePanelHeight)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Tasks"
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.isRestorable = false
        // .statusBar is not enough to stay visible over other apps' fullscreen
        // spaces; .popUpMenu keeps the panel on top there (Spotlight-style).
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentViewController = hosting
        super.init(window: panel)
        panel.delegate = self
        panel.orderOut(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func showPanel() {
        model.prepareForDisplay()
        isExpanded = false
        applyCompactLayout()
        os_log(.info, "TasksPanel show: frame %{public}@", NSStringFromRect(panel.frame))
        let targetFrame = panel.frame
        var startFrame = targetFrame
        startFrame.origin.y += targetFrame.height * 0.85
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        showWindow(nil)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
        focusEditor()
    }

    func hidePanel() {
        model.flush()
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func togglePanel() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Layouts

    private func applyCompactLayout() {
        let placement = NotchPanelGeometry.placement(
            baseHeight: TasksView.basePanelHeight,
            fallbackWidth: Self.fallbackPanelWidth
        )
        hosting.rootView = TasksView(
            model: model,
            mode: .panel,
            onDismiss: { [weak self] in
                self?.hidePanel()
            },
            onExpand: { [weak self] in
                self?.toggleExpanded()
            },
            panelTopInset: placement.topInset,
            panelWidth: placement.width
        )
        panel.setFrame(placement.frame, display: false)
    }

    private func applyExpandedLayout() {
        let screen = panel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(
            width: min(960, visible.width - 120),
            height: min(780, visible.height - 80)
        )
        let frame = NSRect(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        hosting.rootView = TasksView(
            model: model,
            mode: .expanded,
            onDismiss: { [weak self] in
                self?.hidePanel()
            },
            onExpand: { [weak self] in
                self?.toggleExpanded()
            }
        )
        panel.setFrame(frame, display: true, animate: true)
    }

    private func toggleExpanded() {
        isExpanded.toggle()
        if isExpanded {
            applyExpandedLayout()
        } else {
            let placement = NotchPanelGeometry.placement(
                baseHeight: TasksView.basePanelHeight,
                fallbackWidth: Self.fallbackPanelWidth
            )
            hosting.rootView = TasksView(
                model: model,
                mode: .panel,
                onDismiss: { [weak self] in
                    self?.hidePanel()
                },
                onExpand: { [weak self] in
                    self?.toggleExpanded()
                },
                panelTopInset: placement.topInset,
                panelWidth: placement.width
            )
            panel.setFrame(placement.frame, display: true, animate: true)
        }
    }

    private func focusEditor() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(name: .fitbitAirMoodBarFocusTasks, object: nil)
        }
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            model.flush()
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else { return }
        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard panel.isVisible, panel.isKeyWindow else { return event }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "s":
                model.saveNow()
                return nil
            case "o":
                toggleExpanded()
                return nil
            case "r":
                model.reloadNow()
                return nil
            case "w":
                hidePanel()
                return nil
            default:
                return event
            }
        }

        guard flags.subtracting(.shift).isEmpty else { return event }

        if event.keyCode == 53 { // esc
            hidePanel()
            return nil
        }
        return event
    }
}
