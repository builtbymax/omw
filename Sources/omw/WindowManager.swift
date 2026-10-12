import AppKit
import OMWCore

@MainActor
final class WindowManager {
    private let store: ConfigStore
    /// The layout last applied on each display, used to know the columns when moving windows.
    private var activeLayouts: [CGDirectDisplayID: UUID] = [:]

    init(store: ConfigStore) {
        self.store = store
    }

    func activeLayoutID(on screen: NSScreen?) -> UUID? {
        screen.flatMap { activeLayouts[$0.displayID] }
    }

    func apply(_ layout: Layout) {
        guard ensureTrusted(), let screen = AX.targetScreen() else { return }
        let windows = AX.visibleWindows(on: screen)
        let area = screen.axVisibleFrame
        let assignment = Arranger.assign(snapshots(windows), layout: layout, in: area, pinned: true, balanced: true)
        place(windows, assignment, layout: layout, area: area)
        activeLayouts[screen.displayID] = layout.id
        store.config.lastLayoutID = layout.id
    }

    /// Moves the focused window one column left (-1) or right (+1), swapping it with the window that's there.
    func moveFocused(by delta: Int) {
        guard ensureTrusted(),
              let focused = AX.focusedWindow(),
              let focusedID = AX.windowID(of: focused),
              let screen = AX.targetScreen() else { return }
        let layout = layout(for: screen)
        let windows = AX.visibleWindows(on: screen)
        guard let index = windows.firstIndex(where: { $0.windowID == focusedID }) else { return }

        let area = screen.axVisibleFrame
        let current = Arranger.assign(snapshots(windows), layout: layout, in: area, pinned: false, balanced: false)
        guard let next = Arranger.move(index, by: delta, in: current, columnCount: layout.columnCount) else {
            NSSound.beep()
            return
        }
        place(windows, next, layout: layout, area: area)
        activeLayouts[screen.displayID] = layout.id
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
        let columns = Arranger.columns(for: layout, in: area, gap: store.config.gap)
        for (window, column) in zip(windows, assignment) {
            AX.setFrame(window, to: columns[column])
        }
    }

    private func ensureTrusted() -> Bool {
        if AX.isTrusted { return true }
        AX.requestTrust()
        return false
    }
}
