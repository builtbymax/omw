import AppKit
import OMWCore
import SwiftUI

/// Holding the column resize keys (⌃⌥) for a moment shows the layout of the display under the pointer, with a
/// handle in every gap between two columns. Dragging a handle resizes the columns, the windows follow live.
@MainActor
final class ColumnResizeController {
    private let store: ConfigStore
    private let manager: WindowManager
    private let guide = FeedbackPanel(clickThrough: true)
    private let model = ColumnGuideModel()
    private var handles: [(panel: FeedbackPanel, view: ColumnHandleView)] = []
    private var session: WindowManager.ResizeSession?
    private var monitors: [Any] = []
    private var pendingShow: DispatchWorkItem?
    /// The boundary whose handle is being dragged.
    private var dragging: Int?
    private var keyHeld = false
    /// While a window is dragged, the keys belong to that drag.
    private var suppressed = false

    /// True while the handles are on screen.
    var onVisible: ((Bool) -> Void)?

    /// Holding the keys this long shows the handles, so shortcuts like ⌃⌥1 don't flash them.
    private static let delay = 0.3
    private static let handleWidth: CGFloat = 24

    init(store: ConfigStore, manager: WindowManager) {
        self.store = store
        self.manager = manager
        guide.contentView = NSHostingView(rootView: ColumnGuideView(model: model))
    }

    func start() {
        let flags = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        // While a handle is dragged omw gets the events itself.
        let local = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        monitors = [flags, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
    }

    func setSuppressed(_ suppressed: Bool) {
        self.suppressed = suppressed
        if suppressed { cancel() }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            // A shortcut, not a resize.
            cancel()
        case .flagsChanged:
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            keyHeld = modifiers == store.config.columnResizeKeys.flags
            if keyHeld {
                scheduleShow()
            } else if dragging == nil {
                cancel()
            }
        default:
            break
        }
    }

    private func scheduleShow() {
        guard session == nil, pendingShow == nil, store.config.columnResize, !suppressed, AX.isTrusted else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingShow = nil
                self?.show()
            }
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.delay, execute: work)
    }

    private func show() {
        guard keyHeld, let point = CGEvent(source: nil)?.location, let session = manager.beginColumnResize(at: point) else { return }
        self.session = session
        let screen = session.screen
        let count = session.layout.columnCount - 1
        while handles.count < count { handles.append(makeHandle(handles.count)) }
        guide.setFrame(screen.visibleFrame, display: false)
        model.visible = false
        update(session)
        guide.orderFrontRegardless()
        withAnimation(.easeOut(duration: 0.15)) { model.visible = true }
        for (panel, _) in handles.prefix(count) { panel.orderFrontRegardless() }
        onVisible?(true)
    }

    private func cancel() {
        pendingShow?.cancel()
        pendingShow = nil
        guard let session else { return }
        if dragging != nil { manager.endColumnResize(session) }
        self.session = nil
        dragging = nil
        guide.orderOut(nil)
        for (panel, _) in handles { panel.orderOut(nil) }
        onVisible?(false)
    }

    /// Lays out the guide and the handles for the current column widths.
    private func update(_ session: WindowManager.ResizeSession) {
        let area = session.area
        let columns = session.columns
        let gap = CGFloat(max(0, session.gap))
        model.cells = session.cells.map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
        model.columns = columns.map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }
        model.percents = session.layout.fractions.map { Int(($0 * 100).rounded()) }
        model.dragging = dragging
        for (index, (panel, view)) in handles.enumerated() where index < columns.count - 1 {
            let x = columns[index].maxX + gap / 2
            let rect = CGRect(x: x - Self.handleWidth / 2, y: columns[index].minY, width: Self.handleWidth, height: columns[index].height)
            panel.setFrame(NSScreen.fromAX(rect), display: true)
            view.rootView.model.active = dragging == index
            view.rootView.model.blocked = dragging == index && session.blocked
        }
    }

    private func makeHandle(_ boundary: Int) -> (FeedbackPanel, ColumnHandleView) {
        let panel = FeedbackPanel(clickThrough: false)
        let view = ColumnHandleView(rootView: ColumnHandle(model: ColumnHandleModel()))
        view.onDrag = { [weak self] phase in self?.drag(boundary, phase) }
        panel.contentView = view
        return (panel, view)
    }

    private func drag(_ boundary: Int, _ phase: ColumnHandleView.Phase) {
        guard let session else { return }
        switch phase {
        case .began:
            dragging = boundary
            update(session)
        case let .moved(x):
            let blocked = session.blocked
            if manager.resizeColumns(session, boundary: boundary, toX: x) || session.blocked != blocked { update(session) }
        case .ended:
            dragging = nil
            manager.endColumnResize(session)
            if keyHeld { update(session) } else { cancel() }
        }
    }
}

extension ModifierKey {
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }
}

extension [ModifierKey] {
    var flags: NSEvent.ModifierFlags { reduce(into: []) { $0.insert($1.flag) } }
    var symbols: String { map(\.symbol).joined() }
}

// MARK: - Guide

@MainActor
private final class ColumnGuideModel: ObservableObject {
    @Published var cells: [CGRect] = []
    @Published var columns: [CGRect] = []
    @Published var percents: [Int] = []
    @Published var dragging: Int?
    @Published var visible = false
}

/// The cells of the layout with the width of every column, while the handles are shown.
private struct ColumnGuideView: View {
    @ObservedObject var model: ColumnGuideModel

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack(alignment: .topLeading) {
            ForEach(model.cells.indices, id: \.self) { index in
                let rect = model.cells[index]
                shape.strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                    .background(shape.fill(Theme.tileTop.opacity(0.1)))
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
            }
            ForEach(model.columns.indices, id: \.self) { index in
                let rect = model.columns[index]
                // The columns on both sides of the dragged handle stand out.
                let touched = model.dragging.map { $0 == index || $0 + 1 == index } ?? false
                if model.percents.indices.contains(index) {
                    Text("\(model.percents[index])%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(touched ? Theme.tileBottom : Color(hex: 0x141824, opacity: 0.75)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                        .scaleEffect(touched ? 1.1 : 1)
                        .frame(width: rect.width)
                        .offset(x: rect.minX, y: rect.midY - 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(model.visible ? 1 : 0)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: model.dragging)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Handle

@MainActor
private final class ColumnHandleModel: ObservableObject {
    @Published var hovered = false
    @Published var active = false
    /// A window on one side doesn't get any narrower.
    @Published var blocked = false
}

/// A grip in the gap between two columns.
private struct ColumnHandle: View {
    @ObservedObject var model: ColumnHandleModel

    var body: some View {
        let highlighted = model.hovered || model.active
        let grip = model.blocked ? AnyShapeStyle(Color.orange) : highlighted ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.85))
        ZStack {
            // Nearly clear, but not fully: the window server lets clicks through fully transparent pixels.
            Color.white.opacity(0.01)
            Capsule()
                .fill(.white.opacity(highlighted ? 0.35 : 0.15))
                .frame(width: 2)
                .padding(.vertical, 12)
            Capsule()
                .fill(grip)
                .frame(width: highlighted ? 8 : 6, height: highlighted ? 72 : 52)
                .overlay(Capsule().strokeBorder(.black.opacity(0.2)))
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.65), value: highlighted)
        .animation(.easeOut(duration: 0.15), value: model.blocked)
    }
}

/// Handles the drag itself, with the resize cursor. The panel never becomes key, so tracking is always active.
private final class ColumnHandleView: NSHostingView<ColumnHandle> {
    enum Phase {
        case began, moved(CGFloat), ended
    }

    var onDrag: (Phase) -> Void = { _ in }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
                                       owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        rootView.model.hovered = true
    }

    override func mouseExited(with event: NSEvent) {
        rootView.model.hovered = false
        if !rootView.model.active { NSCursor.arrow.set() }
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        onDrag(.began)
    }

    /// AppKit and the Accessibility API share the x axis, only y is flipped.
    override func mouseDragged(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
        onDrag(.moved(NSEvent.mouseLocation.x))
    }

    override func mouseUp(with event: NSEvent) {
        onDrag(.ended)
    }
}
