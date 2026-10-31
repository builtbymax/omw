import AppKit
import OMWCore

/// Watches mouse drags on other apps' windows. Moving a window shows the cell it lands in and snaps it there
/// on release (⇧ without swapping, ⌥ leaves it where it was dropped). Resizing a window at a column edge
/// resizes the column, and the windows next to it follow.
@MainActor
final class DragTracker {
    private enum Mode {
        case pending, move, resize(WindowManager.ResizeSession), ignored
    }

    private final class Drag {
        let windowID: CGWindowID
        let start: CGRect
        var mode = Mode.pending
        var point: CGPoint
        var lastUpdate = Date.distantPast

        init(windowID: CGWindowID, start: CGRect, point: CGPoint) {
            self.windowID = windowID
            self.start = start
            self.point = point
        }
    }

    private let store: ConfigStore
    private let manager: WindowManager
    private let highlight = DropHighlightController()
    private var monitor: Any?
    private var drag: Drag?

    /// True while a window is being moved or a column resized, false when it's over.
    var onDragging: ((Bool) -> Void)?
    /// After every click, a window may have come to the front.
    var onMouseUp: (() -> Void)?

    /// Window frames are read at most this often while dragging.
    private static let interval = 1.0 / 60
    /// Movement below this is a click, not a drag.
    private static let threshold: CGFloat = 2

    init(store: ConfigStore, manager: WindowManager) {
        self.store = store
        self.manager = manager
    }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            drag = nil
            guard store.config.dragToSnap, !SpaceMover.isDragging, AX.isTrusted,
                  let point = event.cgEvent?.location, let window = AX.windowUnder(point) else { return }
            drag = Drag(windowID: window.id, start: window.frame, point: point)
        case .leftMouseDragged:
            guard let drag, let point = event.cgEvent?.location else { return }
            drag.point = point
            guard Date().timeIntervalSince(drag.lastUpdate) >= Self.interval else { return }
            drag.lastUpdate = Date()
            dragged(drag, flags: event.modifierFlags)
        case .flagsChanged:
            if let drag, case .move = drag.mode { updateHighlight(drag, flags: event.modifierFlags) }
        case .leftMouseUp:
            let finished = drag
            drag = nil
            if let finished { released(finished, flags: event.modifierFlags) }
            onMouseUp?()
        default:
            break
        }
    }

    private func dragged(_ drag: Drag, flags: NSEvent.ModifierFlags) {
        switch drag.mode {
        case .pending:
            guard let frame = AX.serverFrame(of: drag.windowID) else { return }
            let resized = abs(frame.width - drag.start.width) > Self.threshold || abs(frame.height - drag.start.height) > Self.threshold
            let moved = abs(frame.minX - drag.start.minX) > Self.threshold || abs(frame.minY - drag.start.minY) > Self.threshold
            if resized {
                if let session = manager.beginResize(drag.windowID, start: drag.start, current: frame) {
                    drag.mode = .resize(session)
                    onDragging?(true)
                    manager.updateResize(session, frame: frame)
                } else {
                    drag.mode = .ignored
                }
            } else if moved {
                drag.mode = .move
                onDragging?(true)
                updateHighlight(drag, flags: flags)
            }
        case .move:
            updateHighlight(drag, flags: flags)
        case let .resize(session):
            if let frame = AX.serverFrame(of: drag.windowID) { manager.updateResize(session, frame: frame) }
        case .ignored:
            break
        }
    }

    private func released(_ drag: Drag, flags: NSEvent.ModifierFlags) {
        switch drag.mode {
        case .move:
            highlight.hide()
            if !flags.contains(.option) {
                let swap = !flags.contains(.shift)
                // Let the app finish its own end of the drag first, or it can put the window back.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.manager.drop(drag.windowID, from: drag.start, at: drag.point, swap: swap)
                }
            }
            onDragging?(false)
        case let .resize(session):
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                let frame = AX.serverFrame(of: drag.windowID) ?? drag.start
                self?.manager.endResize(session, frame: frame)
            }
            onDragging?(false)
        case .pending, .ignored:
            break
        }
    }

    private func updateHighlight(_ drag: Drag, flags: NSEvent.ModifierFlags) {
        guard !flags.contains(.option), let target = manager.dropTarget(at: drag.point, start: drag.start) else {
            highlight.hide()
            return
        }
        highlight.show(target.cell, on: target.screen, swap: !flags.contains(.shift))
    }
}
