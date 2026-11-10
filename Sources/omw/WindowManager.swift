import AppKit
import OMWCore

/// Why a window command did nothing. Hotkeys beep, the CLI prints the message.
enum ActionError: Error {
    case notTrusted, noDisplay, noFocusedWindow, edge, singleDisplay, noNewWindows, nothingToUndo
    case noSpace, spaceShortcutOff(right: Bool), noLayout(display: CGDirectDisplayID)
    case emptyWorkspace, noWorkspaceDisplay

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
        case .noLayout: "No layout is applied on this workspace yet."
        case .emptyWorkspace: "The workspace has no apps pinned yet."
        case .noWorkspaceDisplay: "None of the workspace's displays are connected."
        case let .spaceShortcutOff(right):
            "The Mission Control shortcut \u{201C}Move \(right ? "right" : "left") a space\u{201D} is turned off in System Settings → Keyboard → Keyboard Shortcuts."
        }
    }
}

@MainActor
final class WindowManager {
    private let store: ConfigStore
    /// The layout last applied on each display's Space, used to know the columns when moving windows.
    private var activeLayouts: [DisplaySpace: UUID] = [:]
    /// Windows the active layout placed on each display. Anything else is new to "Refresh Layout".
    private var arrangedWindows: [DisplaySpace: Set<CGWindowID>] = [:]
    /// Frames from before the last arrange, and what was active on each Space it touched, so it can be undone.
    private var undoState: (moves: [(window: ManagedWindow, frame: CGRect)],
                            spaces: [(space: DisplaySpace, layoutID: UUID?, arranged: Set<CGWindowID>?)])?
    /// Bumped by every arrange, so windows of apps a workspace launched stop being placed once something else was applied.
    private var arrangeGeneration = 0
    private let animator = FrameAnimator()
    /// Layouts applied from the launcher without saving them, so "Refresh Layout" still finds them.
    private var unsavedLayouts: [UUID: Layout] = [:]
    /// The active layout with the column widths dragged on each display. Applying a layout again resets them.
    private var adjustedLayouts: [DisplaySpace: Layout] = [:]

    /// Called after a layout was applied with the number of windows that were arranged, and a note
    /// when some couldn't be.
    var onArranged: ((Layout, Int, NSScreen, String?) -> Void)?
    /// Called whenever omw moved windows, so the stack dots can catch up.
    var onWindowsMoved: (() -> Void)?

    init(store: ConfigStore) {
        self.store = store
    }

    var canUndo: Bool { undoState != nil }

    /// Whether the columns on the screen's current Space are known: a layout was applied there, or windows
    /// already fill its cells (after omw restarted).
    func hasLayout(on screen: NSScreen) -> Bool {
        if activeLayouts[screen.space] != nil { return true }
        let cells = Arranger.cells(for: layout(for: screen), in: screen.axVisibleFrame, gap: store.config.gap)
        return AX.visibleWindows(on: screen).contains { window in cells.contains { Arranger.fills(window.frame, $0) } }
    }

    func activeLayoutID(on screen: NSScreen?) -> UUID? {
        screen.flatMap { activeLayouts[$0.space] }
    }

    /// The number of windows that were arranged, and on which display.
    @discardableResult
    func apply(_ layout: Layout, on target: NSScreen? = nil) -> Result<(count: Int, screen: NSScreen), ActionError> {
        guard ensureTrusted() else { return .failure(.notTrusted) }
        guard let screen = target ?? AX.targetScreen() else { return .failure(.noDisplay) }
        let windows = AX.visibleWindows(on: screen).filter { layout.arranges(appID: $0.bundleID) }
        let area = screen.axVisibleFrame
        let assignment = Arranger.assign(snapshots(windows), layout: layout, in: area, pinned: true, balanced: true)
        undoState = (windows.map { ($0, $0.frame) }, [undoEntry(screen.space)])
        arrangeGeneration += 1
        adjustedLayouts[screen.space] = nil
        place(windows, assignment, layout: layout, area: area)
        activeLayouts[screen.space] = layout.id
        arrangedWindows[screen.space] = Set(windows.map(\.windowID))
        if store.layout(id: layout.id) == nil {
            unsavedLayouts[layout.id] = layout
        } else {
            store.config.lastLayoutID = layout.id
        }
        onArranged?(layout, windows.count, screen, nil)
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
        let arranged = (arrangedWindows[screen.space] ?? [])
            .union(windows.filter { window in cells.contains { Arranger.fills(window.frame, $0) } }.map(\.windowID))
        let new = windows.filter { !arranged.contains($0.windowID) }
        guard !new.isEmpty else {
            NSSound.beep()
            return .failure(.noNewWindows)
        }
        let existing = windows.filter { arranged.contains($0.windowID) }
        let assignment = Arranger.assignNew(snapshots(new), existing: snapshots(existing), layout: layout, in: area)
        undoState = (new.map { ($0, $0.frame) }, [undoEntry(screen.space)])
        place(new, assignment, layout: layout, area: area)
        activeLayouts[screen.space] = layout.id
        arrangedWindows[screen.space] = arranged.union(new.map(\.windowID))
        onArranged?(layout, new.count, screen, nil)
        return .success(new.count)
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
        for entry in state.spaces {
            activeLayouts[entry.space] = entry.layoutID
            arrangedWindows[entry.space] = entry.arranged
        }
        onWindowsMoved?()
        return nil
    }

    private func undoEntry(_ space: DisplaySpace) -> (space: DisplaySpace, layoutID: UUID?, arranged: Set<CGWindowID>?) {
        (space, activeLayouts[space], arrangedWindows[space])
    }

    // MARK: Workspaces

    /// Puts every open pinned app of the workspace in its cell, on the workspace's displays that are
    /// connected, and launches the pinned apps that have no window yet. Their windows are placed as
    /// they show up. Windows of other apps stay where they are. Pinned apps whose windows are all on
    /// other Spaces are left alone, opening them would switch to their Space. Returns the number of
    /// windows arranged right away, the number of apps launched and the names of the apps left alone.
    @discardableResult
    func apply(_ workspace: Workspace) -> Result<(count: Int, launched: Int, elsewhere: [String]), ActionError> {
        guard ensureTrusted() else { return .failure(.notTrusted) }
        guard !workspace.apps.isEmpty else { return .failure(.emptyWorkspace) }
        let targets = workspaceTargets(workspace)
        guard let first = targets.first else { return .failure(.noWorkspaceDisplay) }

        let windows = AX.visibleWindows(on: nil)
        var moves: [(window: ManagedWindow, frame: CGRect, crossesDisplays: Bool)] = []
        var placed: [DisplaySpace: Set<CGWindowID>] = [:]
        for window in windows {
            guard let (display, cell) = workspace.placement(of: window.bundleID),
                  let target = targets.first(where: { $0.display == display }) else { continue }
            let cells = Arranger.cells(for: target.layout, in: target.screen.axVisibleFrame, gap: store.config.gap)
            moves.append((window, cells[cell], AX.screen(containing: window.frame) != target.screen))
            placed[target.screen.space, default: []].insert(window.windowID)
        }

        arrangeGeneration += 1
        undoState = (moves.map { ($0.window, $0.window.frame) }, targets.map { undoEntry($0.screen.space) })
        for target in targets {
            let space = target.screen.space
            adjustedLayouts[space] = nil
            activeLayouts[space] = target.layout.id
            arrangedWindows[space] = placed[space] ?? []
            unsavedLayouts[target.layout.id] = target.layout
        }
        // Across displays windows jump: gliding over the gap between screens looks broken.
        for move in moves where move.crossesDisplays { AX.setFrame(move.window, to: move.frame) }
        animator.run(moves.filter { !$0.crossesDisplays }.map { ($0.window, $0.frame) }, animated: store.config.animate)
        onWindowsMoved?()

        let open = Set(windows.compactMap(\.bundleID))
        let missing = workspace.apps.filter { app in
            !open.contains(app) && workspace.placement(of: app).map { p in targets.contains { $0.display == p.display } } == true
        }
        let away = Spaces.appsOnlyElsewhere()
        let elsewhere = NSWorkspace.shared.runningApplications.filter { app in
            app.bundleIdentifier.map(missing.contains) == true && away.contains(app.processIdentifier)
        }
        let skipped = Set(elsewhere.compactMap(\.bundleIdentifier))
        let launched = missing.filter { !skipped.contains($0) }.filter(Self.launch)
        if !launched.isEmpty { placeLaunched(Set(launched), of: workspace, generation: arrangeGeneration) }
        let names = elsewhere.compactMap(\.localizedName)
        onArranged?(first.layout, moves.count, first.screen, Self.elsewhereNote(names))
        return .success((moves.count, launched.count, names))
    }

    /// "Spotify is in another workspace", for pinned apps the workspace left on their Space.
    static func elsewhereNote(_ names: [String]) -> String? {
        switch names.count {
        case 0: nil
        case 1: "\(names[0]) is in another workspace"
        case 2: "\(names[0]) and \(names[1]) are in other workspaces"
        default: "\(names.count) apps are in other workspaces"
        }
    }

    /// The workspace's displays that are connected, with the columns as they're applied.
    private func workspaceTargets(_ workspace: Workspace) -> [(display: String, screen: NSScreen, layout: Layout)] {
        workspace.displays.compactMap { display in
            guard let screen = NSScreen.screens.first(where: { $0.uuid == display.displayID }) else { return nil }
            var layout = display.layout
            layout.name = workspace.name
            layout.pinnedOnly = true
            return (display.displayID, screen, layout)
        }
    }

    /// Opens an app that has no window on the current desktop. A running app is asked to reopen,
    /// which brings back a window, or unhides it.
    private static func launch(_ bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    /// Watches for the windows of apps the workspace launched and puts them in their cells. An app is
    /// done a little after its first window showed up, apps that restore several windows open them one by one.
    private func placeLaunched(_ apps: Set<String>, of workspace: Workspace, generation: Int,
                               firstSeen: [String: Date] = [:], deadline: Date = .now + 20) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, generation == self.arrangeGeneration else { return }
            var firstSeen = firstSeen
            let targets = workspaceTargets(workspace)
            for window in AX.visibleWindows(on: nil) {
                guard let app = window.bundleID, apps.contains(app),
                      let (display, cell) = workspace.placement(of: app),
                      let target = targets.first(where: { $0.display == display }) else { continue }
                let space = target.screen.space
                guard activeLayouts[space] == target.layout.id, arrangedWindows[space]?.contains(window.windowID) != true else { continue }
                let cells = Arranger.cells(for: target.layout, in: target.screen.axVisibleFrame, gap: store.config.gap)
                AX.setFrame(window, to: cells[cell])
                arrangedWindows[space, default: []].insert(window.windowID)
                firstSeen[app] = firstSeen[app] ?? .now
                onWindowsMoved?()
            }
            let done = apps.allSatisfy { firstSeen[$0].map { Date.now.timeIntervalSince($0) > 2 } ?? false }
            guard !done, Date.now < deadline else { return }
            placeLaunched(apps, of: workspace, generation: generation, firstSeen: firstSeen, deadline: deadline)
        }
    }

    /// Moves the focused window one cell left/right (dx) or up/down (dy). With `swap`, the window that's
    /// there takes its old cell, otherwise it stays and the two share the cell.
    @discardableResult
    func moveFocused(dx: Int, dy: Int, swap: Bool = true) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let focused = AX.focusedWindow(),
              let focusedID = AX.windowID(of: focused),
              let screen = AX.targetScreen() else { return .noFocusedWindow }
        guard hasLayout(on: screen) else { return .noLayout(display: screen.displayID) }
        let layout = layout(for: screen)
        let windows = AX.visibleWindows(on: screen)
        guard let index = windows.firstIndex(where: { $0.windowID == focusedID }) else { return .noFocusedWindow }

        let area = screen.axVisibleFrame
        let current = Arranger.assign(snapshots(windows), layout: layout, in: area, pinned: false, balanced: false)
        guard let next = Arranger.move(index, dx: dx, dy: dy, in: current, layout: layout, swap: swap) else {
            NSSound.beep()
            return .edge
        }
        place(windows, next, layout: layout, area: area)
        activeLayouts[screen.space] = layout.id
        arrangedWindows[screen.space] = Set(windows.map(\.windowID))
        return nil
    }

    @discardableResult
    func perform(_ command: WindowCommand) -> ActionError? {
        switch command {
        case .moveLeft: moveFocused(dx: -1, dy: 0)
        case .moveRight: moveFocused(dx: 1, dy: 0)
        case .moveUp: moveFocusedVertically(-1)
        case .moveDown: moveFocusedVertically(1)
        case .moveLeftNoSwap: moveFocused(dx: -1, dy: 0, swap: false)
        case .moveRightNoSwap: moveFocused(dx: 1, dy: 0, swap: false)
        case .moveUpNoSwap: moveFocusedVertically(-1, swap: false)
        case .moveDownNoSwap: moveFocusedVertically(1, swap: false)
        case .nextDisplay: moveFocusedToDisplay(by: 1)
        case .previousDisplay: moveFocusedToDisplay(by: -1)
        case .nextSpace: moveFocusedToSpace(by: 1)
        case .previousSpace: moveFocusedToSpace(by: -1)
        }
    }

    /// In a column with rows, the row above or below. Otherwise the top half, bottom half or full height of the column.
    private func moveFocusedVertically(_ direction: Int, swap: Bool = true) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let window = AX.focusedManagedWindow(), let screen = AX.screen(containing: window.frame) else { return .noFocusedWindow }
        guard hasLayout(on: screen) else { return .noLayout(display: screen.displayID) }
        let layout = layout(for: screen)
        let area = screen.axVisibleFrame
        let index = layout.nearestFilledColumn(to: Arranger.columnIndex(forX: window.frame.midX, layout: layout, in: area))
        if layout.rowCounts[index] > 1 {
            return moveFocused(dx: 0, dy: direction, swap: swap)
        }
        let column = Arranger.columns(for: layout, in: area, gap: store.config.gap)[index]
        let target = Arranger.verticalSlot(for: window.frame, in: column, direction: direction, gap: store.config.gap)
        animator.run([(window, target)], animated: store.config.animate)
        onWindowsMoved?()
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
        guard hasLayout(on: target) else { return .noLayout(display: target.displayID) }
        let from = source.axVisibleFrame, to = target.axVisibleFrame
        let relativeX = from.width > 0 ? (window.frame.midX - from.minX) / from.width : 0.5
        let relativeY = from.height > 0 ? (window.frame.midY - from.minY) / from.height : 0.5
        let layout = layout(for: target)
        let point = CGPoint(x: to.minX + relativeX * to.width, y: to.minY + relativeY * to.height)
        let cell = Arranger.cellIndex(at: point, layout: layout, in: to)
        // Across displays it jumps: gliding over the gap between screens looks broken.
        AX.setFrame(window, to: Arranger.cells(for: layout, in: to, gap: store.config.gap)[cell])
        onWindowsMoved?()
        return nil
    }

    private func moveFocusedToSpace(by delta: Int) -> ActionError? {
        guard ensureTrusted() else { return .notTrusted }
        guard let window = AX.focusedManagedWindow() else { return .noFocusedWindow }
        return SpaceMover.move(window, by: delta)
    }

    private func layout(for screen: NSScreen) -> Layout {
        let layouts = store.config.layouts
        let id = activeLayouts[screen.space] ?? store.config.lastLayoutID
        if let adjusted = adjustedLayouts[screen.space], adjusted.id == id { return adjusted }
        return layouts.first { $0.id == id } ?? id.flatMap { unsavedLayouts[$0] } ?? layouts.first ?? Layout(name: "Halves", ratios: [50, 50])
    }

    private func snapshots(_ windows: [ManagedWindow]) -> [WindowSnapshot] {
        windows.map { WindowSnapshot(appID: $0.bundleID, frame: $0.frame) }
    }

    private func place(_ windows: [ManagedWindow], _ assignment: [Int], layout: Layout, area: CGRect) {
        let cells = Arranger.cells(for: layout, in: area, gap: store.config.gap)
        animator.run(zip(windows, assignment).map { ($0, cells[$1]) }, animated: store.config.animate)
        onWindowsMoved?()
    }

    // MARK: Dragging

    /// Whether windows dragged on `screen` snap into its cells: once a layout was applied there, or when
    /// the window started out in one of them (after omw restarted).
    private func snaps(on screen: NSScreen, start: CGRect) -> Bool {
        activeLayouts[screen.space] != nil
            || Arranger.cells(for: layout(for: screen), in: screen.axVisibleFrame, gap: store.config.gap).contains { Arranger.fills(start, $0) }
    }

    /// A window being moved with the drag modifier held. The windows on each display are looked up once.
    final class MoveSession {
        fileprivate let windowID: CGWindowID
        fileprivate let start: CGRect
        fileprivate lazy var dragged = AX.visibleWindows(on: nil).first { $0.windowID == windowID }
        /// The frontmost other window in every occupied cell, per display.
        fileprivate var occupants: [CGDirectDisplayID: [Int: ManagedWindow]] = [:]

        fileprivate init(windowID: CGWindowID, start: CGRect) {
            self.windowID = windowID
            self.start = start
        }
    }

    /// Where a dragged window lands: every cell of the display, the target cell, and with a swap
    /// the window there and the cell it moves to.
    struct DropPreview {
        let screen: NSScreen
        let cells: [CGRect]
        let target: Int
        let dragged: ManagedWindow?
        let partner: (window: ManagedWindow, cell: Int)?
    }

    /// Nil for windows that can't snap, like fixed-size settings windows.
    func beginMove(_ windowID: CGWindowID, start: CGRect) -> MoveSession? {
        let session = MoveSession(windowID: windowID, start: start)
        guard let dragged = session.dragged, AX.isResizable(dragged) else { return nil }
        return session
    }

    func preview(_ session: MoveSession, at point: CGPoint, swap: Bool) -> DropPreview? {
        guard let screen = NSScreen.screens.first(where: { $0.axFrame.contains(point) }), snaps(on: screen, start: session.start) else { return nil }
        let layout = layout(for: screen)
        let area = screen.axVisibleFrame
        let cells = Arranger.cells(for: layout, in: area, gap: store.config.gap)
        let target = Arranger.cellIndex(at: point, layout: layout, in: area)
        let occupants = session.occupants[screen.displayID] ?? {
            var result: [Int: ManagedWindow] = [:]
            for window in AX.visibleWindows(on: screen) where window.windowID != session.windowID {
                if let cell = cells.firstIndex(where: { Arranger.fills(window.frame, $0) }), result[cell] == nil { result[cell] = window }
            }
            session.occupants[screen.displayID] = result
            return result
        }()
        var partner: (ManagedWindow, Int)?
        if swap, let from = cells.firstIndex(where: { Arranger.fills(session.start, $0) }), from != target, let window = occupants[target] {
            partner = (window, from)
        }
        return DropPreview(screen: screen, cells: cells, target: target, dragged: session.dragged, partner: partner)
    }

    /// Snaps a dragged window into the cell under `point`. With `swap`, the frontmost window in that cell
    /// takes the cell the dragged window came from, if it came from one on the same display.
    @discardableResult
    func drop(_ session: MoveSession, at point: CGPoint, swap: Bool) -> Bool {
        guard AX.isTrusted, let preview = preview(session, at: point, swap: swap),
              let dragged = AX.visibleWindows(on: nil).first(where: { $0.windowID == session.windowID }) else { return false }
        var moves = [(dragged, preview.cells[preview.target])]
        if let partner = preview.partner, let frame = AX.frame(of: partner.window.element) {
            moves.append((partner.window.with(frame: frame), preview.cells[partner.cell]))
        }
        animator.run(moves, animated: store.config.animate)
        activeLayouts[preview.screen.space] = layout(for: preview.screen).id
        arrangedWindows[preview.screen.space, default: []].formUnion(moves.map(\.0.windowID))
        onWindowsMoved?()
        return true
    }

    /// The columns of a display while the resize keys are held. Dragging an edge between two columns moves it,
    /// the windows that fill a cell follow.
    final class ResizeSession {
        let screen: NSScreen
        let area: CGRect
        let gap: Double
        /// The layout with the column widths as dragged so far.
        private(set) var layout: Layout
        /// True when the last move stopped at the narrowest a window gets.
        private(set) var blocked = false
        fileprivate let windows: [(window: ManagedWindow, cell: Int)]
        fileprivate var changed = false
        /// The narrowest each column can get, learned from windows that wouldn't shrink further.
        fileprivate var minWidths: [Int: CGFloat] = [:]
        /// The frame each window was last sent to, so windows whose cell didn't change aren't asked again.
        fileprivate var sent: [CGWindowID: CGRect] = [:]
        /// The width each window reported after it was last sent somewhere.
        fileprivate var reported: [CGWindowID: CGFloat] = [:]
        /// Apps whose enhanced UI is off for the drag, it makes them animate and drop size changes.
        fileprivate var enhancedApps: [AXUIElement]?
        /// The column every cell is in.
        fileprivate let cellColumns: [Int]

        fileprivate init(screen: NSScreen, layout: Layout, gap: Double, windows: [(window: ManagedWindow, cell: Int)]) {
            self.screen = screen
            area = screen.axVisibleFrame
            self.gap = gap
            self.layout = layout
            self.windows = windows
            cellColumns = layout.rowCounts.enumerated().flatMap { Array(repeating: $0.offset, count: $0.element) }
        }

        var columns: [CGRect] { Arranger.columns(for: layout, in: area, gap: gap) }
        var cells: [CGRect] { Arranger.cells(for: layout, in: area, gap: gap) }

        /// Moves the edge between column `boundary` and the next one to `x`, the middle of the gap between them,
        /// but not so far that a window gets narrower than it can. False when the widths didn't change, they snap to 1%.
        fileprivate func move(_ boundary: Int, toX x: CGFloat) -> Bool {
            let columns = columns
            guard columns.indices.contains(boundary + 1) else { return false }
            let half = CGFloat(max(0, gap)) / 2
            let lowest = minWidths[boundary].map { columns[boundary].minX + $0 + half } ?? -.infinity
            let highest = minWidths[boundary + 1].map { columns[boundary + 1].maxX - $0 - half } ?? .infinity
            let clamped = lowest <= highest ? min(max(x, lowest), highest) : x
            blocked = clamped != x
            var position = Arranger.boundaryPosition(forEdge: clamped - half, boundary: boundary, layout: layout, in: area, gap: gap)
            guard position.isFinite else { return false }
            var ratios = layout.resizedRatios(movingBoundary: boundary, to: position, step: 0.01)
            // Snapping to 1% can still cut a little into a minimum width.
            for _ in 0..<3 {
                var candidate = layout
                candidate.ratios = ratios
                let widths = Arranger.columns(for: candidate, in: area, gap: gap).map(\.width)
                if let width = minWidths[boundary], widths[boundary] < width - 1 {
                    position += 0.01
                } else if let width = minWidths[boundary + 1], widths[boundary + 1] < width - 1 {
                    position -= 0.01
                } else {
                    break
                }
                ratios = layout.resizedRatios(movingBoundary: boundary, to: position, step: 0.01)
            }
            guard ratios != layout.fractions.map({ ($0 * 10_000).rounded() / 100 }) else { return false }
            layout.ratios = ratios
            changed = true
            return true
        }

        /// Sends every window whose cell changed there. True when a window turned out not to get as narrow
        /// as its cell, its column then has a minimum width.
        fileprivate func place() -> Bool {
            if enhancedApps == nil {
                var apps: [pid_t: AXUIElement] = [:]
                for (window, _) in windows where AX.hasEnhancedUI(window) { apps[window.pid ?? 0] = window.app }
                enhancedApps = Array(apps.values)
                for app in apps.values { AX.setEnhancedUI(app, false) }
            }
            let cells = cells
            var learned = false
            for (window, cell) in windows {
                let target = cells[cell]
                let previous = sent[window.windowID] ?? window.frame
                guard target != previous else { continue }
                AX.setFrameFast(window, to: target)
                sent[window.windowID] = target
                guard let width = AX.frame(of: window.element)?.width else { continue }
                // Still wider after shrinking twice in a row: not an app that is just slow, it won't go narrower.
                if target.width < previous.width, width > target.width + 2,
                   let last = reported[window.windowID], abs(last - width) < 1 {
                    let column = cellColumns[cell]
                    minWidths[column] = max(minWidths[column] ?? 0, width)
                    learned = true
                }
                reported[window.windowID] = width
            }
            return learned
        }

        fileprivate func restoreEnhancedUI() {
            for app in enhancedApps ?? [] { AX.setEnhancedUI(app, true) }
            enhancedApps = nil
        }
    }

    /// Column resizing for the display under `point`, once a layout with more than one column was applied there
    /// or windows already fill its cells.
    /// The display has no layout on its current Space when that's why it failed.
    func beginColumnResize(at point: CGPoint) -> Result<ResizeSession, ActionError> {
        guard AX.isTrusted else { return .failure(.notTrusted) }
        guard let screen = NSScreen.screens.first(where: { $0.axFrame.contains(point) }) else { return .failure(.noDisplay) }
        let layout = layout(for: screen)
        let cells = Arranger.cells(for: layout, in: screen.axVisibleFrame, gap: store.config.gap)
        let windows = AX.visibleWindows(on: screen).compactMap { window in
            cells.firstIndex { Arranger.fills(window.frame, $0) }.map { (window, $0) }
        }
        guard activeLayouts[screen.space] != nil || !windows.isEmpty else { return .failure(.noLayout(display: screen.displayID)) }
        // One column has no edge to drag.
        guard layout.columnCount > 1 else { return .failure(.edge) }
        return .success(ResizeSession(screen: screen, layout: layout, gap: store.config.gap, windows: windows))
    }

    /// Moves a column edge, the windows follow right away. False when nothing changed.
    @discardableResult
    func resizeColumns(_ session: ResizeSession, boundary: Int, toX x: CGFloat) -> Bool {
        guard session.move(boundary, toX: x) else { return false }
        // A window that wouldn't shrink pulls the edge back to where it still fits.
        if session.place(), session.move(boundary, toX: x) { _ = session.place() }
        return true
    }

    /// Keeps the new column widths on the display until a layout is applied again, and settles every window in its cell.
    func endColumnResize(_ session: ResizeSession) {
        guard session.changed else {
            session.restoreEnhancedUI()
            return
        }
        let id = session.screen.space
        adjustedLayouts[id] = session.layout
        activeLayouts[id] = session.layout.id
        let cells = session.cells
        settle(session.windows.map { ($0.window, cells[$0.cell]) }, attempts: 3) { session.restoreEnhancedUI() }
        onWindowsMoved?()
    }

    /// Sets the frames, then checks again a moment later: apps still busy with the drag can end up
    /// a step behind.
    private func settle(_ moves: [(ManagedWindow, CGRect)], attempts: Int, then done: @escaping () -> Void) {
        var pending: [(ManagedWindow, CGRect)] = []
        for (window, target) in moves {
            // Frames changed during the drag, and setFrame skips windows that already seem in place.
            let current = window.with(frame: AX.frame(of: window.element) ?? window.frame)
            let off = [current.frame.minX - target.minX, current.frame.minY - target.minY,
                       current.frame.width - target.width, current.frame.height - target.height]
            if off.allSatisfy({ abs($0) < 1 }) { continue }
            AX.setFrame(current, to: target)
            pending.append((window, target))
        }
        guard attempts > 1, !pending.isEmpty else {
            done()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return done() }
            settle(pending, attempts: attempts - 1, then: done)
        }
    }

    // MARK: Stacks

    var hasActiveLayout: Bool { !activeLayouts.isEmpty }

    /// Cells with more than one window in them on displays with an active layout, windows front to back.
    func stacks() -> [(screen: NSScreen, cell: CGRect, windows: [ManagedWindow])] {
        NSScreen.screens.filter { activeLayouts[$0.space] != nil }.flatMap { screen in
            let cells = Arranger.cells(for: layout(for: screen), in: screen.axVisibleFrame, gap: store.config.gap)
            let windows = AX.visibleWindows(on: screen)
            return zip(cells, Arranger.stacks(windows.map(\.frame), cells: cells))
                .filter { $0.1.count > 1 }
                .map { (screen, $0.0, $0.1.map { windows[$0] }) }
        }
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
