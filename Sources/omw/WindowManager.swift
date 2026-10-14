import AppKit
import OMWCore

/// Why a window command did nothing. Hotkeys beep, the CLI prints the message.
enum ActionError: Error {
    case notTrusted, noDisplay, noFocusedWindow, edge, singleDisplay, noNewWindows, nothingToUndo
    case noSpace, spaceShortcutOff(right: Bool)

    var message: String {
        switch self {
        case .notTrusted: "omw needs Accessibility access: System Settings → Privacy & Security → Accessibility."
        case .noDisplay: "No display found."
        case .noFocusedWindow: "No focused window to move."
        case .edge: "There's no column or row in that direction."
        case .singleDisplay: "There's only one display."
        case .noNewWindows: "No new windows to place."
        case .nothingToUndo: "Nothing to undo."
        case .noSpace: "There's no workspace in that direction."
        case let .spaceShortcutOff(right):
            "The Mission Control shortcut \u{201C}Move \(right ? "right" : "left") a space\u{201D} is turned off in System Settings → Keyboard → Keyboard Shortcuts."
        }
    }
}

@MainActor
final class WindowManager {
    private let store: ConfigStore
    /// The layout last applied on each display, used to know the columns when moving windows.
    private var activeLayouts: [CGDirectDisplayID: UUID] = [:]
    /// Windows the active layout placed on each display. Anything else is new to "Refresh Layout".
    private var arrangedWindows: [CGDirectDisplayID: Set<CGWindowID>] = [:]
    /// Frames from before the last arrange, so it can be undone.
    private var undoState: (moves: [(window: ManagedWindow, frame: CGRect)], displayID: CGDirectDisplayID, layoutID: UUID?,
                            arranged: Set<CGWindowID>?)?
    private let animator = FrameAnimator()

    /// Called after a layout was applied with the number of windows that were arranged.
    var onArranged: ((Layout, Int, NSScreen) -> Void)?

    init(store: ConfigStore) {
        self.store = store
    }

    var canUndo: Bool { undoState != nil }

    func activeLayoutID(on screen: NSScreen?) -> UUID? {
        screen.flatMap { activeLayouts[$0.displayID] }
    }

    /// The number of windows that were arranged, and on which display.
    @discardableResult
    func apply(_ layout: Layout, on target: NSScreen? = nil) -> Result<(count: Int, screen: NSScreen), ActionError> {
        guard ensureTrusted() else { return .failure(.notTrusted) }
        guard let screen = target ?? AX.targetScreen() else { return .failure(.noDisplay) }
        let windows = AX.visibleWindows(on: screen).filter { layout.arranges(appID: $0.bundleID) }
        let area = screen.axVisibleFrame
        let assignment = Arranger.assign(snapshots(windows), layout: layout, in: area, pinned: true, balanced: true)
        undoState = (windows.map { ($0, $0.frame) }, screen.displayID, activeLayouts[screen.displayID], arrangedWindows[screen.displayID])
        place(windows, assignment, layout: layout, area: area)
        activeLayouts[screen.displayID] = layout.id
        arrangedWindows[screen.displayID] = Set(windows.map(\.windowID))
        store.config.lastLayoutID = layout.id
        onArranged?(layout, windows.count, screen)
        return .success((windows.count, screen))
    }

    /// Places windows opened since the active layout was applied, without touching the ones already in it.
    /// Windows that already fill a cell count as placed too, so this also works after omw restarted.
    @discardableResult
    func refresh(on target: NSScreen? = nil) -> Result<Int, ActionError> {
        guard ensureTrusted() else { return .failure(.notTrusted) }
        guard let screen = target ?? AX.targetScreen() else { return .failure(.noDisplay) }
        let layout = layout(for: screen)
        let area = screen.axVisibleFrame
        let cells = Arranger.cells(for: layout, in: area, gap: store.config.gap)
        let windows = AX.visibleWindows(on: screen).filter { layout.arranges(appID: $0.bundleID) }
        let arranged = (arrangedWindows[screen.displayID] ?? [])
            .union(windows.filter { window in cells.contains { Self.matches(window.frame, $0) } }.map(\.windowID))
        let new = windows.filter { !arranged.contains($0.windowID) }
        guard !new.isEmpty else {
            NSSound.beep()
            return .failure(.noNewWindows)
        }
        let existing = windows.filter { arranged.contains($0.windowID) }
        let assignment = Arranger.assignNew(snapshots(new), existing: snapshots(existing), layout: layout, in: area)
        undoState = (new.map { ($0, $0.frame) }, screen.displayID, activeLayouts[screen.displayID], arrangedWindows[screen.displayID])
        place(new, assignment, layout: layout, area: area)
        activeLayouts[screen.displayID] = layout.id
        arrangedWindows[screen.displayID] = arranged.union(new.map(\.windowID))
        onArranged?(layout, new.count, screen)
        return .success(new.count)
    }

    /// Apps round frames to their own size steps (e.g. terminals), so allow some slack.
    private static func matches(_ frame: CGRect, _ cell: CGRect) -> Bool {
        abs(frame.minX - cell.minX) < 4 && abs(frame.minY - cell.minY) < 4
            && abs(frame.width - cell.width) < 24 && abs(frame.height - cell.height) < 24
    }

    /// Puts the windows of the last arrange back where they were.
    @discardableResult
    func undo() -> ActionError? {
        guard let state = undoState else { return .nothingToUndo }
        undoState = nil
        // The windows sit in their columns now, so the moves start from there.
        let moves = state.moves.compactMap { move -> (ManagedWindow, CGRect)? in
            guard let current = AX.frame(of: move.window.element) else { return nil }
            return (move.window.with(frame: current), move.frame)
        }
        animator.run(moves, animated: store.config.animate)
        activeLayouts[state.displayID] = state.layoutID
        arrangedWindows[state.displayID] = state.arranged
        return nil
    }

    /// Moves the focused window one cell left/right (dx) or up/down (dy), swapping it with the window that's there.
    @discardableResult
    func moveFocused(dx: Int, dy: Int) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let focused = AX.focusedWindow(),
              let focusedID = AX.windowID(of: focused),
              let screen = AX.targetScreen() else { return .noFocusedWindow }
        let layout = layout(for: screen)
        let windows = AX.visibleWindows(on: screen)
        guard let index = windows.firstIndex(where: { $0.windowID == focusedID }) else { return .noFocusedWindow }

        let area = screen.axVisibleFrame
        let current = Arranger.assign(snapshots(windows), layout: layout, in: area, pinned: false, balanced: false)
        guard let next = Arranger.move(index, dx: dx, dy: dy, in: current, layout: layout) else {
            NSSound.beep()
            return .edge
        }
        place(windows, next, layout: layout, area: area)
        activeLayouts[screen.displayID] = layout.id
        arrangedWindows[screen.displayID] = Set(windows.map(\.windowID))
        return nil
    }

    @discardableResult
    func perform(_ command: WindowCommand) -> ActionError? {
        switch command {
        case .moveLeft: moveFocused(dx: -1, dy: 0)
        case .moveRight: moveFocused(dx: 1, dy: 0)
        case .moveUp: moveFocusedVertically(-1)
        case .moveDown: moveFocusedVertically(1)
        case .nextDisplay: moveFocusedToDisplay(by: 1)
        case .previousDisplay: moveFocusedToDisplay(by: -1)
        case .nextSpace: moveFocusedToSpace(by: 1)
        case .previousSpace: moveFocusedToSpace(by: -1)
        }
    }

    /// In a column with rows, the row above or below. Otherwise the top half, bottom half or full height of the column.
    private func moveFocusedVertically(_ direction: Int) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let window = AX.focusedManagedWindow(), let screen = AX.screen(containing: window.frame) else { return .noFocusedWindow }
        let layout = layout(for: screen)
        let area = screen.axVisibleFrame
        let index = layout.nearestFilledColumn(to: Arranger.columnIndex(forX: window.frame.midX, layout: layout, in: area))
        if layout.rowCounts[index] > 1 {
            return moveFocused(dx: 0, dy: direction)
        }
        let column = Arranger.columns(for: layout, in: area, gap: store.config.gap)[index]
        let target = Arranger.verticalSlot(for: window.frame, in: column, direction: direction, gap: store.config.gap)
        animator.run([(window, target)], animated: store.config.animate)
        return nil
    }

    /// Moves the focused window to the cell at the same relative position on the display left (-1) or right (+1) of its current one.
    private func moveFocusedToDisplay(by delta: Int) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let window = AX.focusedManagedWindow(), let source = AX.screen(containing: window.frame) else { return .noFocusedWindow }
        let screens = NSScreen.leftToRight
        guard screens.count > 1, let index = screens.firstIndex(of: source) else {
            NSSound.beep()
            return .singleDisplay
        }
        let target = screens[(index + delta + screens.count) % screens.count]
        let from = source.axVisibleFrame, to = target.axVisibleFrame
        let relativeX = from.width > 0 ? (window.frame.midX - from.minX) / from.width : 0.5
        let relativeY = from.height > 0 ? (window.frame.midY - from.minY) / from.height : 0.5
        let layout = layout(for: target)
        let point = CGPoint(x: to.minX + relativeX * to.width, y: to.minY + relativeY * to.height)
        let cell = Arranger.cellIndex(at: point, layout: layout, in: to)
        // Across displays it jumps: gliding over the gap between screens looks broken.
        AX.setFrame(window, to: Arranger.cells(for: layout, in: to, gap: store.config.gap)[cell])
        return nil
    }

    private func moveFocusedToSpace(by delta: Int) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let window = AX.focusedManagedWindow() else { return .noFocusedWindow }
        return SpaceMover.move(window, by: delta)
    }

    private func layout(for screen: NSScreen) -> Layout {
        let layouts = store.config.layouts
        let id = activeLayouts[screen.displayID] ?? store.config.lastLayoutID
        return layouts.first { $0.id == id } ?? layouts.first ?? Layout(name: "Halves", ratios: [50, 50])
    }

    private func snapshots(_ windows: [ManagedWindow]) -> [WindowSnapshot] {
        windows.map { WindowSnapshot(appID: $0.bundleID, frame: $0.frame) }
    }

    private func place(_ windows: [ManagedWindow], _ assignment: [Int], layout: Layout, area: CGRect) {
        let cells = Arranger.cells(for: layout, in: area, gap: store.config.gap)
        animator.run(zip(windows, assignment).map { ($0, cells[$1]) }, animated: store.config.animate)
    }

    private func ensureTrusted() -> Bool {
        if AX.isTrusted { return true }
        AX.requestTrust()
        return false
    }
}

/// Glides windows to their new frames with an ease-out curve, front-to-back with a small stagger.
@MainActor
final class FrameAnimator {
    private var timer: Timer?

    private static let duration = 0.22
    private static let stagger = 0.03
    private static let frameInterval = 1.0 / 60

    func run(_ moves: [(ManagedWindow, CGRect)], animated: Bool) {
        timer?.invalidate()
        timer = nil
        // Apps with "enhanced UI" animate frame changes themselves, so they jump straight to the end.
        let animatable = animated ? moves.filter { !AX.hasEnhancedUI($0.0) } : []
        for move in moves where !animatable.contains(where: { $0.0.windowID == move.0.windowID }) {
            AX.setFrame(move.0, to: move.1)
        }
        guard !animatable.isEmpty else { return }

        let start = Date()
        var finished = Set<Int>()
        let total = Self.duration + Self.stagger * Double(animatable.count - 1)
        timer = Timer.scheduledTimer(withTimeInterval: Self.frameInterval, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                let elapsed = Date().timeIntervalSince(start)
                for (index, (window, target)) in animatable.enumerated() {
                    let t = (elapsed - Self.stagger * Double(index)) / Self.duration
                    guard t > 0, !finished.contains(index) else { continue }
                    if t >= 1 {
                        finished.insert(index)
                        AX.setFrame(window, to: target)
                    } else {
                        AX.setFrameFast(window, to: Self.interpolate(window.frame, target, Self.easeOut(t)))
                    }
                }
                if finished.count == animatable.count || elapsed >= total + 0.5 {
                    timer.invalidate()
                    self?.timer = nil
                }
            }
        }
    }

    private static func easeOut(_ t: Double) -> Double {
        // Slight overshoot-free spring feel: cubic ease-out.
        1 - pow(1 - t, 3)
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        let t = CGFloat(t)
        return CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
                      width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}
