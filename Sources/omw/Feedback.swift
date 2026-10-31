import AppKit
import OMWCore
import SwiftUI

/// Click-through, transparent panel that covers a display.
private final class FeedbackPanel: NSPanel {
    /// Panels that belong to the windows of one desktop pass false for `allSpaces`, so they stay on it.
    init(clickThrough: Bool, allSpaces: Bool = true) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = allSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle] : [.ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = clickThrough
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Ghost columns

@MainActor
private final class GhostModel: ObservableObject {
    @Published var columns: [CGRect] = []
    @Published var visible = false
}

/// Dashed blueprint columns drawn on the real display while browsing layouts in the launcher.
@MainActor
final class GhostColumnsController {
    private let panel = FeedbackPanel(clickThrough: true)
    private let model = GhostModel()

    init() {
        panel.contentView = NSHostingView(rootView: GhostView(model: model))
    }

    func show(_ layout: Layout, on screen: NSScreen, gap: Double, below window: NSWindow) {
        let area = screen.axVisibleFrame
        let columns = Arranger.cells(for: layout, in: area, gap: gap)
            .map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
        if panel.frame != screen.visibleFrame {
            panel.setFrame(screen.visibleFrame, display: false)
            model.columns = columns
        }
        if !panel.isVisible {
            model.columns = columns
            panel.order(.below, relativeTo: window.windowNumber)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            model.columns = columns
        }
        withAnimation(.easeOut(duration: 0.16)) { model.visible = true }
    }

    func hide() {
        model.visible = false
        panel.orderOut(nil)
    }
}

private struct GhostView: View {
    @ObservedObject var model: GhostModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(model.columns.indices, id: \.self) { index in
                let rect = model.columns[index]
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                ZStack {
                    shape.fill(Theme.tileTop.opacity(0.12))
                    shape.strokeBorder(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.visible ? 1 : 0)
    }
}

// MARK: - HUD

@MainActor
private final class HUDModel: ObservableObject {
    @Published var layout: Layout?
    @Published var count = 0
    @Published var visible = false
    var onUndo: () -> Void = {}
}

/// "Arranged 5 windows" confirmation at the bottom of the display, with Undo.
@MainActor
final class HUDController {
    /// Room around the pill for its shadow (radius 20, y 10), so the panel edge never clips it.
    private static let size = NSSize(width: 540, height: 130)
    private static let shadowInset: CGFloat = 34
    private let panel = FeedbackPanel(clickThrough: false)
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    init(undo: @escaping () -> Void) {
        panel.setContentSize(Self.size)
        panel.contentView = NSHostingView(rootView: HUDView(model: model, bottomInset: Self.shadowInset))
        model.onUndo = { [weak self] in
            undo()
            self?.hide()
        }
    }

    func show(_ layout: Layout, count: Int, on screen: NSScreen) {
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 40 - Self.shadowInset))
        model.layout = layout
        model.count = count
        model.visible = false
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { model.visible = true }

        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        withAnimation(.easeIn(duration: 0.18)) { model.visible = false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            if self?.model.visible == false { self?.panel.orderOut(nil) }
        }
    }
}

private struct HUDView: View {
    @ObservedObject var model: HUDModel
    let bottomInset: CGFloat
    @State private var bounce = false

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            if model.visible, let layout = model.layout {
                HStack(spacing: 12) {
                    LayoutIcon(layout: layout, size: 36)
                        .scaleEffect(bounce ? 1.12 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.count == 1 ? "Arranged 1 window" : "Arranged \(model.count) windows")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Text(layout.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.55))
                            Text(layout.ratioLabel).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 26)
                    Button("Undo") { model.onUndo() }
                        .buttonStyle(.glassCapsule(.secondary))
                }
                .padding(10)
                .padding(.trailing, 4)
                // A dark base under the content keeps the white text readable when light windows shine through the glass.
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(hex: 0x141824, opacity: 0.6)))
                .glassSurface(cornerRadius: 30, tint: Color(hex: 0x141824, opacity: 0.55))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .onAppear {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45).delay(0.12)) { bounce = true }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.3)) { bounce = false }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, bottomInset)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Drop target

@MainActor
private final class DropHighlightModel: ObservableObject {
    @Published var cell: CGRect?
    @Published var swap = true
}

/// The cell a dragged window lands in, drawn on its display while the window is moved.
@MainActor
final class DropHighlightController {
    private let panel = FeedbackPanel(clickThrough: true)
    private let model = DropHighlightModel()

    init() {
        panel.contentView = NSHostingView(rootView: DropHighlightView(model: model))
    }

    /// `cell` in Accessibility API coordinates.
    func show(_ cell: CGRect, on screen: NSScreen, swap: Bool) {
        let area = screen.axVisibleFrame
        let local = cell.offsetBy(dx: -area.minX, dy: -area.minY)
        if panel.frame != screen.visibleFrame || !panel.isVisible {
            panel.setFrame(screen.visibleFrame, display: false)
            model.cell = local
            panel.orderFrontRegardless()
        }
        model.swap = swap
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { model.cell = local }
    }

    func hide() {
        model.cell = nil
        panel.orderOut(nil)
    }
}

private struct DropHighlightView: View {
    @ObservedObject var model: DropHighlightModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let rect = model.cell {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                ZStack {
                    shape.fill(Theme.tileTop.opacity(0.18))
                    shape.strokeBorder(.white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: model.swap ? [] : [8, 6]))
                }
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Stack dots

@MainActor
private final class StackModel: ObservableObject {
    struct Item: Identifiable {
        let id: CGWindowID
        let title: String
    }

    /// The windows in a cell in a stable order, so the dots don't jump around when one comes to the front.
    @Published var items: [Item] = []
    @Published var frontID: CGWindowID?
    var onSelect: (CGWindowID) -> Void = { _ in }

    /// The window `delta` dots away from the front one, wrapping around.
    func cycle(_ delta: Int) {
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == frontID } ?? 0
        onSelect(items[(index + delta + items.count) % items.count].id)
    }
}

/// Scrolling over the dots flips through the windows of the cell.
private final class StackHostingView: NSHostingView<StackDotsView> {
    private var scrolled: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { scrolled = 0 }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY
        scrolled += event.hasPreciseScrollingDeltas ? delta : delta * 10
        guard abs(scrolled) >= 24 else { return }
        rootView.model.cycle(scrolled > 0 ? -1 : 1)
        scrolled = 0
    }
}

/// A row of dots on a cell with more than one window, one per window. The window in front has the
/// highlighted dot, clicking another dot brings that window to the front.
@MainActor
final class StackIndicatorController {
    private let store: ConfigStore
    private let manager: WindowManager
    private var panels: [(panel: NSPanel, model: StackModel)] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var suspended = false

    private static let dotSize: CGFloat = 14
    private static let height: CGFloat = 24

    init(store: ConfigStore, manager: WindowManager) {
        self.store = store
        self.manager = manager
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observe(workspace, name) { $0.scheduleRefresh() }
        }
        // The dots of the old desktop shouldn't show up on the new one.
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { controller in
            controller.hideAll()
            controller.scheduleRefresh()
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.scheduleRefresh() }
        // Windows that close or open don't announce themselves, so look again every now and then.
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (StackIndicatorController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }

    /// Hides the dots while a window is dragged, they come back once it's over.
    func setSuspended(_ suspended: Bool) {
        self.suspended = suspended
        if suspended {
            pending?.cancel()
            hideAll()
        } else {
            scheduleRefresh()
        }
    }

    /// Looks again once windows have settled, e.g. after omw moved them or another app came to the front.
    func scheduleRefresh(after delay: TimeInterval = 0.45) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.refresh() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refresh() {
        guard store.config.showStackIndicator, !suspended, manager.hasActiveLayout, AX.isTrusted else {
            hideAll()
            return
        }
        let stacks = manager.stacks()
        while panels.count < stacks.count { panels.append(makePanel()) }
        for ((panel, model), stack) in zip(panels, stacks) {
            let items = stack.windows.sorted { $0.windowID < $1.windowID }.map { window in
                StackModel.Item(id: window.windowID, title: AX.copy(window.element, kAXTitleAttribute) as? String ?? window.bundleID ?? "Window")
            }
            let windows = Dictionary(stack.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            model.onSelect = { [weak self] id in
                guard let window = windows[id] else { return }
                AX.raise(window)
                model.frontID = id
                self?.scheduleRefresh(after: 0.3)
            }
            model.items = items
            model.frontID = stack.windows.first?.windowID
            // Bottom center of the cell, just inside it.
            let width = CGFloat(items.count) * Self.dotSize + 16
            let rect = CGRect(x: stack.cell.midX - width / 2, y: stack.cell.maxY - Self.height - 10, width: width, height: Self.height)
            panel.setFrame(NSScreen.fromAX(rect).integral, display: true)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for (panel, _) in panels.dropFirst(stacks.count) { panel.orderOut(nil) }
    }

    private func makePanel() -> (NSPanel, StackModel) {
        let model = StackModel()
        let panel = FeedbackPanel(clickThrough: false, allSpaces: false)
        panel.contentView = StackHostingView(rootView: StackDotsView(model: model, dotSize: Self.dotSize))
        return (panel, model)
    }

    private func hideAll() {
        for (panel, _) in panels { panel.orderOut(nil) }
    }
}

private struct StackDotsView: View {
    @ObservedObject var model: StackModel
    let dotSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            ForEach(model.items) { item in
                let front = item.id == model.frontID
                Circle()
                    .fill(front ? Theme.tileTop : Color.white.opacity(0.5))
                    .frame(width: front ? 8 : 6, height: front ? 8 : 6)
                    .frame(width: dotSize, height: dotSize)
                    .contentShape(Rectangle())
                    .onTapGesture { model.onSelect(item.id) }
                    .help(item.title)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color(hex: 0x141824, opacity: 0.6)))
        .glassSurface(cornerRadius: 12, tint: Color(hex: 0x141824, opacity: 0.55))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.frontID)
        .environment(\.colorScheme, .dark)
    }
}
