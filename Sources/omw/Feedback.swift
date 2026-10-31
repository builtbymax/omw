import AppKit
import OMWCore
import SwiftUI

/// Click-through, transparent panel that covers a display.
final class FeedbackPanel: NSPanel {
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

// MARK: - Drag preview

@MainActor
private final class DragPreviewModel: ObservableObject {
    @Published var cells: [CGRect] = []
    @Published var target: CGRect?
    @Published var draggedIcon: NSImage?
    /// The window that makes room, where it goes.
    @Published var partner: CGRect?
    @Published var partnerIcon: NSImage?
    @Published var visible = false
}

/// The layout on the display while a window is dragged with the drag modifier: every cell, the one the window
/// lands in, and the window that swaps places with it gliding to the cell the dragged window came from.
@MainActor
final class DragPreviewController {
    private let panel = FeedbackPanel(clickThrough: true)
    private let model = DragPreviewModel()
    private static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)

    init() {
        panel.contentView = NSHostingView(rootView: DragPreviewView(model: model))
    }

    func show(_ preview: WindowManager.DropPreview) {
        let area = preview.screen.axVisibleFrame
        let local = { (rect: CGRect) in rect.offsetBy(dx: -area.minX, dy: -area.minY) }
        let cells = preview.cells.map(local)
        let target = cells[preview.target]
        let partner = preview.partner.map { cells[$0.cell] }
        if panel.frame != preview.screen.visibleFrame || !panel.isVisible {
            panel.setFrame(preview.screen.visibleFrame, display: false)
            model.cells = cells
            model.target = target
            model.partner = nil
            model.visible = false
            panel.orderFrontRegardless()
        }
        model.draggedIcon = preview.dragged.flatMap(Self.icon)
        if let window = preview.partner?.window {
            if model.partner == nil {
                // The window there starts out in the target cell and slides over to make room.
                model.partner = target
                model.partnerIcon = Self.icon(window)
            }
        } else if model.partner != nil {
            withAnimation(Self.spring) { model.partner = nil }
        }
        // A runloop later, so a partner that just appeared animates from where it was set.
        DispatchQueue.main.async { [model] in
            withAnimation(Self.spring) {
                model.cells = cells
                model.target = target
                if let partner { model.partner = partner }
                model.visible = true
            }
        }
    }

    func hide() {
        model.visible = false
        model.partner = nil
        panel.orderOut(nil)
    }

    private static func icon(_ window: ManagedWindow) -> NSImage? {
        window.pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
    }
}

private struct DragPreviewView: View {
    @ObservedObject var model: DragPreviewModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .topLeading) {
            ForEach(model.cells.indices, id: \.self) { index in
                let rect = model.cells[index]
                shape.strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .background(shape.fill(Color.black.opacity(0.12)))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if let rect = model.partner {
                tile(icon: model.partnerIcon, fill: .white.opacity(0.16), border: .white.opacity(0.6))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity)
            }
            if let rect = model.target {
                tile(icon: model.draggedIcon, fill: Theme.tileTop.opacity(0.28), border: .white.opacity(0.9))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.visible ? 1 : 0)
        .scaleEffect(model.visible ? 1 : 0.98)
    }

    private func tile(icon: NSImage?, fill: Color, border: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            shape.fill(fill)
            shape.strokeBorder(border, lineWidth: 2)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            }
        }
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
    @Published var vertical = false
    /// The pointer is over the pill, and over which dot.
    @Published var inside = false
    @Published var hovered: CGWindowID?
    var onSelect: (CGWindowID) -> Void = { _ in }

    func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        onSelect(items[index].id)
    }

    /// The window `delta` dots away from the front one, wrapping around.
    func cycle(_ delta: Int) {
        guard !items.isEmpty else { return }
        let index = items.firstIndex { $0.id == frontID } ?? 0
        select((index + delta + items.count) % items.count)
    }
}

/// Handles clicks and scrolling on the dots itself: SwiftUI gestures miss clicks now and then in a panel
/// that never becomes key.
private final class StackHostingView: NSHostingView<StackDotsView>, NSViewToolTipOwner {
    private var scrolled: CGFloat = 0

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        if let index = dotIndex(at: convert(event.locationInWindow, from: nil)) { rootView.model.select(index) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        // Always active: the panel never becomes key.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

    override func mouseExited(with event: NSEvent) {
        rootView.model.hovered = nil
        rootView.model.inside = false
        NSCursor.arrow.set()
    }

    private func hover(_ event: NSEvent) {
        NSCursor.pointingHand.set()
        let model = rootView.model
        let id = dotIndex(at: convert(event.locationInWindow, from: nil)).map { model.items[$0].id }
        if model.hovered != id { model.hovered = id }
        if !model.inside { model.inside = true }
    }

    /// Scrolling flips through the windows of the cell.
    override func scrollWheel(with event: NSEvent) {
        if event.phase == .began || event.phase == .mayBegin { scrolled = 0 }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? -event.scrollingDeltaX : event.scrollingDeltaY
        scrolled += event.hasPreciseScrollingDeltas ? delta : delta * 10
        guard abs(scrolled) >= 24 else { return }
        rootView.model.cycle(scrolled > 0 ? -1 : 1)
        scrolled = 0
    }

    func updateToolTips() {
        removeAllToolTips()
        for index in rootView.model.items.indices { addToolTip(dotRect(index), owner: self, userData: nil) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        dotIndex(at: point).map { rootView.model.items[$0].title } ?? ""
    }

    /// The dots are centered along the pill, `dotSize` apart.
    private func dotRect(_ index: Int) -> NSRect {
        let size = rootView.dotSize
        let count = CGFloat(rootView.model.items.count)
        if rootView.model.vertical {
            let top = (bounds.height - count * size) / 2 + CGFloat(index) * size
            return NSRect(x: 0, y: isFlipped ? top : bounds.height - top - size, width: bounds.width, height: size)
        }
        return NSRect(x: (bounds.width - count * size) / 2 + CGFloat(index) * size, y: 0, width: size, height: bounds.height)
    }

    private func dotIndex(at point: NSPoint) -> Int? {
        rootView.model.items.indices.first { dotRect($0).contains(point) }
    }
}

/// A row of dots on a cell with more than one window, one per window. The window in front has the
/// highlighted dot, clicking another dot brings that window to the front.
@MainActor
final class StackIndicatorController {
    private let store: ConfigStore
    private let manager: WindowManager
    private var panels: [(panel: NSPanel, view: StackHostingView, model: StackModel)] = []
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
        let position = store.config.stackIndicatorPosition
        for ((panel, view, model), stack) in zip(panels, stacks) {
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
            model.vertical = position.isVertical
            panel.setFrame(NSScreen.fromAX(Self.frame(for: items.count, in: stack.cell, at: position)).integral, display: true)
            view.updateToolTips()
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for (panel, _, _) in panels.dropFirst(stacks.count) { panel.orderOut(nil) }
    }

    /// The pill centered on one edge of the cell, just inside it.
    private static func frame(for count: Int, in cell: CGRect, at position: StackIndicatorPosition) -> CGRect {
        let length = CGFloat(count) * dotSize + 16
        let inset: CGFloat = 10
        switch position {
        case .top: return CGRect(x: cell.midX - length / 2, y: cell.minY + inset, width: length, height: height)
        case .bottom: return CGRect(x: cell.midX - length / 2, y: cell.maxY - height - inset, width: length, height: height)
        case .left: return CGRect(x: cell.minX + inset, y: cell.midY - length / 2, width: height, height: length)
        case .right: return CGRect(x: cell.maxX - height - inset, y: cell.midY - length / 2, width: height, height: length)
        }
    }

    private func makePanel() -> (NSPanel, StackHostingView, StackModel) {
        let model = StackModel()
        let panel = FeedbackPanel(clickThrough: false, allSpaces: false)
        let view = StackHostingView(rootView: StackDotsView(model: model, dotSize: Self.dotSize))
        panel.contentView = view
        return (panel, view, model)
    }

    private func hideAll() {
        for (panel, _, _) in panels { panel.orderOut(nil) }
    }
}

private struct StackDotsView: View {
    @ObservedObject var model: StackModel
    let dotSize: CGFloat

    var body: some View {
        let stack = model.vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        // Clicks and tooltips are handled by StackHostingView.
        stack {
            ForEach(model.items) { item in
                let front = item.id == model.frontID
                let hovered = item.id == model.hovered
                Circle()
                    .fill(front ? Theme.tileTop : Color.white.opacity(hovered ? 0.9 : model.inside ? 0.65 : 0.5))
                    .frame(width: 6, height: 6)
                    .scaleEffect(hovered ? 1.6 : front ? 1.33 : 1)
                    .frame(width: dotSize, height: dotSize)
            }
        }
        .scaleEffect(model.inside ? 1.06 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color(hex: 0x141824, opacity: 0.6)))
        .glassSurface(cornerRadius: 12, tint: Color(hex: 0x141824, opacity: 0.55))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.frontID)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: model.hovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: model.inside)
        .environment(\.colorScheme, .dark)
    }
}
