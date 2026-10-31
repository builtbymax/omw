import AppKit
import OMWCore

/// Watches mouse drags on other apps' windows. Moving a window previews the layout with the cell it lands in and
/// snaps it there on release: swapping with the window there, with ⇧ sharing the cell, with ⌥ not at all.
@MainActor
final class DragTracker {
    private enum Mode {
        case pending, move(WindowManager.MoveSession), ignored
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
    private let preview = DragPreviewController()
    private var monitor: Any?
    private var drag: Drag?

    /// True while a window is being moved, false when it's over.
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
            if let drag, case let .move(session) = drag.mode { updatePreview(session, at: drag.point, flags: event.modifierFlags) }
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
            if abs(frame.width - drag.start.width) > Self.threshold || abs(frame.height - drag.start.height) > Self.threshold {
                // Resized, not moved.
                drag.mode = .ignored
            } else if abs(frame.minX - drag.start.minX) > Self.threshold || abs(frame.minY - drag.start.minY) > Self.threshold {
                let session = manager.beginMove(drag.windowID, start: drag.start)
                drag.mode = .move(session)
                onDragging?(true)
                updatePreview(session, at: drag.point, flags: flags)
            }
        case let .move(session):
            updatePreview(session, at: drag.point, flags: flags)
        case .ignored:
            break
        }
    }

    private func released(_ drag: Drag, flags: NSEvent.ModifierFlags) {
        guard case let .move(session) = drag.mode else { return }
        preview.hide()
        if !flags.contains(.option) {
            let swap = !flags.contains(.shift)
            // Let the app finish its own end of the drag first, or it can put the window back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.manager.drop(session, at: drag.point, swap: swap)
            }
        }
        onDragging?(false)
    }

    private func updatePreview(_ session: WindowManager.MoveSession, at point: CGPoint, flags: NSEvent.ModifierFlags) {
        guard !flags.contains(.option), let target = manager.preview(session, at: point, swap: !flags.contains(.shift)) else {
            preview.hide()
            return
        }
        preview.show(target)
    }
}
