import AppKit
import OMWCore
import ScreenCaptureKit
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
    struct Notice {
        let title: String
        let detail: String
    }

    @Published var layout: Layout?
    @Published var count = 0
    /// Something that didn't work, shown instead of the layout.
    @Published var notice: Notice?
    @Published var visible = false
    var onUndo: () -> Void = {}
    var onChooseLayout: () -> Void = {}
}

/// "Arranged 5 windows" confirmation at the bottom of the display, with Undo. Also tells when a command
/// needs a layout first.
@MainActor
final class HUDController {
    /// Room around the pill for its shadow (radius 20, y 10), so the panel edge never clips it.
    private static let size = NSSize(width: 540, height: 130)
    private static let shadowInset: CGFloat = 34
    private let panel = FeedbackPanel(clickThrough: false)
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    init(undo: @escaping () -> Void, chooseLayout: @escaping () -> Void) {
        panel.setContentSize(Self.size)
        panel.contentView = NSHostingView(rootView: HUDView(model: model, bottomInset: Self.shadowInset))
        model.onUndo = { [weak self] in
            undo()
            self?.hide()
        }
        model.onChooseLayout = { [weak self] in
            self?.hide()
            chooseLayout()
        }
    }

    func show(_ layout: Layout, count: Int, on screen: NSScreen) {
        model.layout = layout
        model.count = count
        model.notice = nil
        present(on: screen)
    }

    /// A command that needs the columns of a layout ran on a workspace without one.
    func showNoLayout(on screen: NSScreen, shortcut: Shortcut?) {
        let detail = shortcut.map { "Apply one first, e.g. with \($0.displayString)." } ?? "Apply one first from the launcher."
        // Showing again while it's up only restarts its timer, so holding a key doesn't make it flicker.
        let showing = panel.isVisible && model.visible && model.notice != nil
        model.notice = HUDModel.Notice(title: "No layout on this workspace", detail: detail)
        if showing {
            scheduleHide()
        } else {
            present(on: screen)
        }
    }

    private func present(on screen: NSScreen) {
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - Self.size.width / 2, y: visible.minY + 40 - Self.shadowInset))
        model.visible = false
        panel.orderFrontRegardless()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { model.visible = true }
        scheduleHide()
    }

    private func scheduleHide() {
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
            if model.visible, let notice = model.notice {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.orange)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.orange.opacity(0.16)))
                        .scaleEffect(bounce ? 1.12 : 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(notice.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(notice.detail)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 26)
                    Button("Choose Layout") { model.onChooseLayout() }
                        .buttonStyle(.glassCapsule(.secondary))
                }
                .padding(10)
                .padding(.trailing, 4)
                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(hex: 0x141824, opacity: 0.6)))
                .glassSurface(cornerRadius: 30, tint: Color(hex: 0x141824, opacity: 0.55))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                .onAppear {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45).delay(0.12)) { bounce = true }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7).delay(0.3)) { bounce = false }
                }
            } else if model.visible, let layout = model.layout {
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
    /// The key that leaves the window where it's dropped.
    @Published var hint = ""
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

    func show(_ preview: WindowManager.DropPreview, hint: String) {
        model.hint = hint
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
                    .overlay(alignment: .bottom) {
                        Text(model.hint)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color(hex: 0x141824, opacity: 0.7)))
                            .padding(.bottom, 16)
                    }
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
        let bundleID: String?
        let size: CGSize
    }

    /// The windows in a cell in the order the user gave them, else a stable one, so the dots don't
    /// jump around when one comes to the front.
    @Published var items: [Item] = []
    @Published var frontID: CGWindowID?
    @Published var vertical = false
    /// The pointer is over the pill, and over which dot.
    @Published var inside = false
    @Published var hovered: CGWindowID?
    /// The dots jiggle and can be dragged into another order.
    @Published var reordering = false
    /// The dot being dragged while reordering.
    @Published var lifted: CGWindowID?
    var onSelect: (CGWindowID) -> Void = { _ in }
    /// The new order of the windows after a dot was dropped.
    var onReorder: ([CGWindowID]) -> Void = { _ in }
    /// The hovered dot and its frame on screen, nil when the pointer left the dots.
    var onHover: (Item?, NSRect) -> Void = { _, _ in }

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

    func move(_ id: CGWindowID, to index: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }), from != index, items.indices.contains(index) else { return }
        items.insert(items.remove(at: from), at: index)
    }
}

/// Handles clicks, press-and-hold reordering and scrolling on the dots itself: SwiftUI gestures miss
/// clicks now and then in a panel that never becomes key.
private final class StackHostingView: NSHostingView<StackDotsView> {
    private var scrolled: CGFloat = 0
    private var pressed: Int?
    private var holdTimer: Timer?
    private var monitors: [Any] = []

    private static let holdDuration: TimeInterval = 0.45

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let model = rootView.model
        pressed = dotIndex(at: convert(event.locationInWindow, from: nil))
        guard let pressed else { return }
        model.onHover(nil, .zero)
        if model.reordering {
            lift(pressed)
            return
        }
        // Holding a dot starts reordering, a click brings its window to the front.
        let timer = Timer(timeInterval: Self.holdDuration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginReordering() }
        }
        RunLoop.main.add(timer, forMode: .common)
        holdTimer = timer
    }

    override func mouseDragged(with event: NSEvent) {
        let model = rootView.model
        guard let lifted = model.lifted else { return }
        let slot = slot(at: convert(event.locationInWindow, from: nil))
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { model.move(lifted, to: slot) }
    }

    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate()
        holdTimer = nil
        let model = rootView.model
        let point = convert(event.locationInWindow, from: nil)
        defer { pressed = nil }
        guard model.reordering else {
            if let pressed, pressed == dotIndex(at: point) { model.select(pressed) }
            return
        }
        if model.lifted != nil {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) { model.lifted = nil }
            model.onReorder(model.items.map(\.id))
        }
        if !bounds.contains(point) { endReordering() }
    }

    private func beginReordering() {
        holdTimer = nil
        let model = rootView.model
        guard !model.reordering, let pressed else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { model.reordering = true }
        lift(pressed)
        // The panel never becomes key, so Esc and clicks elsewhere only reach global monitors.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return }
            MainActor.assumeIsolated { self?.endReordering() }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.endReordering() }
        }) { monitors.append(monitor) }
    }

    func endReordering() {
        holdTimer?.invalidate()
        holdTimer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        let model = rootView.model
        guard model.reordering else { return }
        if model.lifted != nil { model.onReorder(model.items.map(\.id)) }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            model.lifted = nil
            model.reordering = false
        }
    }

    private func lift(_ index: Int) {
        let model = rootView.model
        guard model.items.indices.contains(index) else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { model.lifted = model.items[index].id }
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
        rootView.model.onHover(nil, .zero)
        NSCursor.arrow.set()
    }

    private func hover(_ event: NSEvent) {
        NSCursor.pointingHand.set()
        let model = rootView.model
        let index = dotIndex(at: convert(event.locationInWindow, from: nil))
        let id = index.map { model.items[$0].id }
        if !model.inside { model.inside = true }
        guard model.hovered != id else { return }
        model.hovered = id
        if let index, !model.reordering, let window {
            model.onHover(model.items[index], window.convertToScreen(convert(dotRect(index), to: nil)))
        } else {
            model.onHover(nil, .zero)
        }
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

    /// The dot position closest to `point` along the pill, also when the pointer is past either end.
    private func slot(at point: NSPoint) -> Int {
        let size = rootView.dotSize
        let count = rootView.model.items.count
        let offset: CGFloat
        if rootView.model.vertical {
            let top = isFlipped ? point.y : bounds.height - point.y
            offset = top - (bounds.height - CGFloat(count) * size) / 2
        } else {
            offset = point.x - (bounds.width - CGFloat(count) * size) / 2
        }
        return min(max(Int((offset / size).rounded(.down)), 0), count - 1)
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
    private let preview = StackPreviewController()
    /// Position of each window among the dots of its cell, as the user ordered them.
    private var order: [CGWindowID: Int] = [:]

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
        // Don't pull the dots from under the pointer while one is dragged.
        guard !panels.contains(where: { $0.model.lifted != nil }) else { return }
        let stacks = manager.stacks()
        while panels.count < stacks.count { panels.append(makePanel()) }
        let position = store.config.stackIndicatorPosition
        let previewStyle = store.config.stackPreview
        if previewStyle == .none { preview.hide() }
        for ((panel, view, model), stack) in zip(panels, stacks) {
            let rank = { [order] (id: CGWindowID) in order[id] ?? Int.max }
            let items = stack.windows
                .sorted { (rank($0.windowID), $0.windowID) < (rank($1.windowID), $1.windowID) }
                .map { window in
                    StackModel.Item(id: window.windowID, title: AX.copy(window.element, kAXTitleAttribute) as? String ?? window.bundleID ?? "Window",
                                    bundleID: window.bundleID, size: window.frame.size)
                }
            // Another cell's windows now: reordering was meant for the old ones.
            if Set(items.map(\.id)) != Set(model.items.map(\.id)) { view.endReordering() }
            let windows = Dictionary(stack.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })
            model.onSelect = { [weak self] id in
                guard let window = windows[id] else { return }
                AX.raise(window)
                model.frontID = id
                self?.scheduleRefresh(after: 0.3)
            }
            model.onReorder = { [weak self] ids in
                for (index, id) in ids.enumerated() { self?.order[id] = index }
            }
            model.onHover = { [weak self] item, dot in
                guard let item, previewStyle != .none else { self?.preview.hide(); return }
                self?.preview.show(item, near: dot, position: position, style: previewStyle)
            }
            model.items = items
            model.frontID = stack.windows.first?.windowID
            model.vertical = position.isVertical
            panel.setFrame(NSScreen.fromAX(Self.frame(for: items.count, in: stack.cell, at: position)).integral, display: true)
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        for (panel, view, _) in panels.dropFirst(stacks.count) {
            view.endReordering()
            panel.orderOut(nil)
        }
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
        preview.hide()
        for (panel, view, _) in panels {
            view.endReordering()
            panel.orderOut(nil)
        }
    }
}

private struct StackDotsView: View {
    @ObservedObject var model: StackModel
    let dotSize: CGFloat

    var body: some View {
        let stack = model.vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        // Clicks and hovering are handled by StackHostingView.
        TimelineView(.animation(paused: !model.reordering)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            stack {
                ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                    dot(item, jiggle: model.reordering && item.id != model.lifted ? jiggle(time, index) : .zero)
                }
            }
        }
        .scaleEffect(model.inside || model.reordering ? 1.06 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Capsule().fill(Color(hex: 0x141824, opacity: 0.6)))
        .overlay(Capsule().strokeBorder(Theme.tileTop.opacity(model.reordering ? 0.8 : 0), lineWidth: 1.5))
        .glassSurface(cornerRadius: 12, tint: Color(hex: 0x141824, opacity: 0.55))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.frontID)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: model.hovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: model.inside)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.reordering)
        .environment(\.colorScheme, .dark)
    }

    private func dot(_ item: StackModel.Item, jiggle: CGSize) -> some View {
        let front = item.id == model.frontID
        let hovered = item.id == model.hovered
        let lifted = item.id == model.lifted
        let scale: CGFloat = lifted ? 2 : model.reordering ? 1.33 : hovered ? 1.6 : front ? 1.33 : 1
        return Circle()
            .fill(front ? Theme.tileTop : Color.white.opacity(lifted ? 1 : hovered ? 0.9 : model.inside ? 0.65 : 0.5))
            .frame(width: 6, height: 6)
            .scaleEffect(scale)
            .shadow(color: .black.opacity(lifted ? 0.5 : 0), radius: 2, y: 1)
            .offset(jiggle)
            .frame(width: dotSize, height: dotSize)
            .zIndex(lifted ? 1 : 0)
    }

    /// A small wobble like home screen icons that can be moved, out of step from dot to dot.
    private func jiggle(_ time: TimeInterval, _ index: Int) -> CGSize {
        let phase = Double(index) * 1.7
        return CGSize(width: sin(time * 22 + phase) * 1.1, height: cos(time * 19 + phase) * 1.1)
    }
}

// MARK: - Stack preview

@MainActor
private final class StackPreviewModel: ObservableObject {
    @Published var title = ""
    @Published var bundleID: String?
    @Published var image: CGImage?
    @Published var thumbnailSize: CGSize = .zero
    @Published var iconOnly = false
}

/// Next to the dots, the window behind the hovered dot. As a card with its app, title and, if omw may
/// record the screen, a thumbnail (omw never asks for Screen Recording just for this), or just its app icon.
@MainActor
private final class StackPreviewController {
    private let panel = FeedbackPanel(clickThrough: true, allSpaces: false)
    private let model = StackPreviewModel()
    private var shownID: CGWindowID?
    private var capture: Task<Void, Never>?
    private var thumbnails: [CGWindowID: (image: CGImage, date: Date)] = [:]

    private static let width: CGFloat = 220
    private static let iconSize: CGFloat = 36
    /// Room around the card for its shadow.
    private static let margin: CGFloat = 12

    init() {
        panel.contentView = NSHostingView(rootView: StackPreviewView(model: model, margin: Self.margin))
    }

    func show(_ item: StackModel.Item, near dot: NSRect, position: StackIndicatorPosition, style: StackPreviewStyle) {
        let iconOnly = style == .icon
        let aspect = item.size.width > 0 ? item.size.height / item.size.width : 0.625
        let thumbnail = CGSize(width: Self.width - 16, height: min(max((Self.width - 16) * aspect, 80), 150))
        let content = iconOnly ? CGSize(width: Self.iconSize, height: Self.iconSize) : CGSize(width: Self.width, height: thumbnail.height + 42)
        let size = CGSize(width: content.width + Self.margin * 2, height: content.height + Self.margin * 2)

        shownID = item.id
        model.title = item.title
        model.bundleID = item.bundleID
        model.thumbnailSize = thumbnail
        model.iconOnly = iconOnly
        let cached = thumbnails[item.id].flatMap { Date().timeIntervalSince($0.date) < 5 ? $0.image : nil }
        model.image = cached

        // Next to the pill on the side facing into the cell.
        let gap: CGFloat = (iconOnly ? 8 : 14) - Self.margin
        var origin: CGPoint
        switch position {
        case .top: origin = CGPoint(x: dot.midX - size.width / 2, y: dot.minY - gap - size.height)
        case .bottom: origin = CGPoint(x: dot.midX - size.width / 2, y: dot.maxY + gap)
        case .left: origin = CGPoint(x: dot.maxX + gap, y: dot.midY - size.height / 2)
        case .right: origin = CGPoint(x: dot.minX - gap - size.width, y: dot.midY - size.height / 2)
        }
        if let visible = (NSScreen.screens.first { $0.frame.contains(CGPoint(x: dot.midX, y: dot.midY)) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size).integral, display: true)
        panel.orderFrontRegardless()

        guard !iconOnly, cached == nil else { return }
        capture?.cancel()
        let id = item.id
        capture = Task { [weak self] in
            guard let image = await Self.thumbnail(of: id, size: thumbnail), !Task.isCancelled, let self else { return }
            self.thumbnails[id] = (image, Date())
            if self.shownID == id { self.model.image = image }
        }
    }

    func hide() {
        capture?.cancel()
        capture = nil
        shownID = nil
        panel.orderOut(nil)
    }

    /// Nil without Screen Recording access, which is only checked, never requested.
    private static func thumbnail(of id: CGWindowID, size: CGSize) async -> CGImage? {
        guard CGPreflightScreenCaptureAccess(),
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
              let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let configuration = SCStreamConfiguration()
        let scale = max(1, min(window.frame.width / size.width, window.frame.height / size.height))
        configuration.width = Int(window.frame.width / scale * 2)
        configuration.height = Int(window.frame.height / scale * 2)
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                           configuration: configuration)
    }
}

private struct StackPreviewView: View {
    @ObservedObject var model: StackPreviewModel
    let margin: CGFloat

    var body: some View {
        if model.iconOnly {
            if let icon = AppIdentity(bundleID: model.bundleID).icon {
                Image(nsImage: icon).resizable().frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
                    .padding(margin)
            }
        } else {
            card
        }
    }

    private var card: some View {
        let app = AppIdentity(bundleID: model.bundleID)
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                shape.fill(LinearGradient(colors: [Color(hex: 0x1E4FD8, opacity: 0.5), Color(hex: 0x5B2BB5, opacity: 0.5)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                if let image = model.image {
                    Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fit)
                } else if let icon = app.icon {
                    Image(nsImage: icon).resizable().frame(width: 48, height: 48)
                }
            }
            .frame(width: model.thumbnailSize.width, height: model.thumbnailSize.height)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.15)))
            HStack(spacing: 6) {
                if let icon = app.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                Text(model.title.isEmpty ? app.name : model.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(height: 18)
        }
        .padding(8)
        .glassSurface(cornerRadius: 14, tint: Color(hex: 0x141824, opacity: 0.7))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .padding(margin)
        .environment(\.colorScheme, .dark)
    }
}
