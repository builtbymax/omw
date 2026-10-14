import CoreGraphics
import Foundation
import OMWCore
import Testing

private let screen = CGRect(x: 0, y: 25, width: 1000, height: 800)
private let focus = Layout(name: "Focus", ratios: [20, 60, 20])

/// A window centered at `x` percent of the screen width.
private func window(_ app: String, at x: Double = 50) -> WindowSnapshot {
    WindowSnapshot(appID: app, frame: CGRect(x: x * 10 - 100, y: 100, width: 200, height: 400))
}

@Suite struct ArrangerTests {
    @Test func columnsFillTheAreaWithGaps() {
        let columns = Arranger.columns(for: focus, in: screen, gap: 10)
        #expect(columns.count == 3)
        #expect(columns[0].minX == 10)
        #expect(columns[2].maxX == 990)
        #expect(columns[1].minX == columns[0].maxX + 10)
        #expect(columns[1].width > columns[0].width * 2.9)
        #expect(columns.allSatisfy { $0.minY == 35 && $0.height == 780 })
    }

    @Test func extraWindowsWrapIntoTheSameColumns() {
        // Slack and Claude already sit left/right, the rest are stacked in the middle.
        let windows = [window("slack", at: 10), window("vscode"), window("claude", at: 90), window("spotify"), window("linear")]
        let result = Arranger.assign(windows, layout: focus, in: screen, pinned: true, balanced: true)
        #expect(result == [0, 1, 2, 1, 0])
    }

    @Test func emptyColumnsGetFilledFirst() {
        let windows = (0..<5).map { window("app\($0)", at: 10) }
        let result = Arranger.assign(windows, layout: focus, in: screen, pinned: true, balanced: true)
        #expect(result == [0, 0, 1, 2, 1])
    }

    @Test func pinnedAppsGoToTheirColumn() {
        var layout = focus
        layout.pins = ["vscode": 1]
        let windows = [window("slack"), window("vscode", at: 10), window("claude")]
        let result = Arranger.assign(windows, layout: layout, in: screen, pinned: true, balanced: true)
        #expect(result[1] == 1)
        #expect(Set(result) == [0, 1, 2])
    }

    @Test func reapplyingKeepsTheArrangement() {
        let windows = [window("a"), window("b"), window("c"), window("d"), window("e")]
        let first = Arranger.assign(windows, layout: focus, in: screen, pinned: true, balanced: true)
        let columns = Arranger.columns(for: focus, in: screen, gap: 8)
        let placed = zip(windows, first).map { WindowSnapshot(appID: $0.appID, frame: columns[$1]) }
        let second = Arranger.assign(placed, layout: focus, in: screen, pinned: true, balanced: true)
        #expect(first == second)
    }

    @Test func newWindowsFillTheEmptiestCells() {
        let existing = [window("a", at: 10), window("b", at: 50), window("c", at: 50)]
        let result = Arranger.assignNew([window("d"), window("e"), window("f")], existing: existing, layout: focus, in: screen)
        #expect(result == [2, 0, 2])
    }

    @Test func newPinnedWindowsGoToTheirCell() {
        var layout = focus
        layout.pins = ["vscode": 1]
        let result = Arranger.assignNew([window("vscode", at: 90)], existing: [window("a", at: 50)], layout: layout, in: screen)
        #expect(result == [1])
    }

    @Test func moveSwapsWithTheFrontmostWindowInTheTargetColumn() {
        // index 0 is focused in column 1; column 0 has windows 1 (front) and 3.
        let assignment = [1, 0, 2, 0]
        #expect(Arranger.move(0, dx: -1, dy: 0, in: assignment, layout: focus) == [0, 1, 2, 0])
        #expect(Arranger.move(0, dx: 1, dy: 0, in: assignment, layout: focus) == [2, 0, 1, 0])
        #expect(Arranger.move(1, dx: -1, dy: 0, in: assignment, layout: focus) == nil)
        #expect(Arranger.move(0, dx: 0, dy: 1, in: assignment, layout: focus) == nil)
    }

    @Test func movingUpAndDownUsesHalvesAndReturnsToFullHeight() {
        let column = CGRect(x: 10, y: 35, width: 300, height: 780)
        let top = Arranger.verticalSlot(for: column, in: column, direction: -1, gap: 10)
        #expect(top == CGRect(x: 10, y: 35, width: 300, height: 385))
        let bottom = Arranger.verticalSlot(for: column, in: column, direction: 1, gap: 10)
        #expect(bottom == CGRect(x: 10, y: 430, width: 300, height: 385))
        #expect(Arranger.verticalSlot(for: top, in: column, direction: 1, gap: 10) == column)
        #expect(Arranger.verticalSlot(for: bottom, in: column, direction: -1, gap: 10) == column)
        #expect(Arranger.verticalSlot(for: top, in: column, direction: -1, gap: 10) == top)
    }

    @Test func moveIntoEmptyColumn() {
        #expect(Arranger.move(0, dx: 1, dy: 0, in: [0, 1], layout: focus) == [1, 0])
        #expect(Arranger.move(1, dx: 1, dy: 0, in: [0, 1], layout: focus) == [0, 2])
    }
}

/// 2x20/60/2x20: cells 0 and 1 on the left, 2 in the middle, 3 and 4 on the right.
private let grid = Layout(name: "Grid", ratios: [20, 60, 20], rows: [2, 1, 2])

@Suite struct RowTests {
    @Test func cellsSplitColumnsIntoRows() {
        let cells = Arranger.cells(for: grid, in: screen, gap: 10)
        #expect(cells.count == 5)
        #expect(cells[0].minY == 35 && cells[0].height == 385)
        #expect(cells[1].minY == 430 && cells[1].maxY == 815)
        #expect(cells[2].height == 780)
        #expect(cells[3].minX == cells[4].minX)
    }

    @Test func windowsFillEveryCellBeforeStacking() {
        let windows = (0..<6).map { window("app\($0)") }
        let result = Arranger.assign(windows, layout: grid, in: screen, pinned: true, balanced: true)
        #expect(Set(result) == [0, 1, 2, 3, 4])
    }

    @Test func windowsStayInTheirRow() {
        let cells = Arranger.cells(for: grid, in: screen, gap: 8)
        let windows = [4, 0, 2, 1, 3].map { WindowSnapshot(appID: "app\($0)", frame: cells[$0]) }
        #expect(Arranger.assign(windows, layout: grid, in: screen, pinned: true, balanced: true) == [4, 0, 2, 1, 3])
    }

    @Test func movingBetweenRowsAndColumns() {
        #expect(grid.neighbour(of: 0, dx: 0, dy: 1) == 1)
        #expect(grid.neighbour(of: 1, dx: 0, dy: 1) == nil)
        #expect(grid.neighbour(of: 1, dx: 1, dy: 0) == 2)
        // From the full-height middle column into the upper row on either side.
        #expect(grid.neighbour(of: 2, dx: 1, dy: 0) == 3)
        #expect(grid.neighbour(of: 2, dx: -1, dy: 0) == 0)
        #expect(grid.neighbour(of: 4, dx: -1, dy: 0) == 2)
        #expect(Arranger.move(0, dx: 0, dy: 1, in: [0, 1], layout: grid) == [1, 0])
    }

    @Test func parsesAndLabelsRows() throws {
        let parsed = try #require(Layout.parse("2x20/60/2x20"))
        #expect(parsed.ratios == [20, 60, 20])
        #expect(parsed.rows == [2, 1, 2])
        #expect(Layout.parse("2 x 20 / 60")?.rows == [2, 1])
        #expect(Layout.parse("20/60/20")?.rows == [])
        #expect(Layout.parse("5x20/80") == nil)
        #expect(Layout.parse("x20") == nil)
        #expect(grid.ratioLabel == "2x20/60/2x20")
        #expect(grid.rowName(of: 0) == "Top")
        #expect(grid.rowName(of: 1) == "Bottom")
        #expect(grid.rowName(of: 2) == nil)
    }

    @Test func pinsFollowTheirCellWhenTheStructureChanges() {
        var layout = grid
        layout.pins = ["mail": 1, "code": 2, "music": 4]
        // Adding a row to the middle column shifts the cells to its right.
        let split = layout.settingRows(2, inColumn: 1)
        #expect(split.pins == ["mail": 1, "code": 2, "music": 5])
        // Removing the left rows moves the bottom-left pin to the only row left.
        let merged = layout.settingRows(1, inColumn: 0)
        #expect(merged.pins == ["mail": 0, "code": 1, "music": 3])
        #expect(layout.removingColumn(at: 0).pins == ["mail": 0, "code": 0, "music": 2])
        #expect(layout.addingColumn().rowCounts == [2, 1, 1, 2])
    }

    @Test func rowsOnlyShowUpInTheConfigWhenUsed() throws {
        let encoded = try String(decoding: JSONEncoder().encode(focus), as: UTF8.self)
        #expect(!encoded.contains("rows"))
        let decoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(grid))
        #expect(decoded.rowCounts == [2, 1, 2])
    }
}

/// _20/60/_20: one centered cell, the sides stay free.
private let center = Layout(name: "Center", ratios: [20, 60, 20], rows: [0, 1, 0])

@Suite struct EmptyColumnTests {
    @Test func onlyTheMiddleGetsWindows() {
        let cells = Arranger.cells(for: center, in: screen, gap: 0)
        #expect(cells == [CGRect(x: 200, y: 25, width: 600, height: 800)])
        let windows = [window("a", at: 5), window("b"), window("c", at: 95)]
        #expect(Arranger.assign(windows, layout: center, in: screen, pinned: true, balanced: true) == [0, 0, 0])
    }

    @Test func parsesAndLabelsEmptyColumns() throws {
        let parsed = try #require(Layout.parse("_20/60/_20"))
        #expect(parsed.rows == [0, 1, 0])
        #expect(center.ratioLabel == "_20/60/_20")
        #expect(Layout.parse("_50/_50") == nil)
        #expect(Layout.parse("_2x20/80") == nil)
        #expect(Layout.parse("_20/2x80")?.rows == [0, 2])
    }

    @Test func movesSkipEmptyColumns() {
        let layout = Layout(name: "x", ratios: [30, 20, 50], rows: [1, 0, 1])
        #expect(layout.neighbour(of: 0, dx: 1, dy: 0) == 1)
        #expect(layout.neighbour(of: 1, dx: -1, dy: 0) == 0)
        #expect(center.neighbour(of: 0, dx: 1, dy: 0) == nil)
    }

    @Test func theLastColumnWithWindowsStays() {
        #expect(!center.canEmpty(column: 1))
        #expect(center.settingRows(0, inColumn: 1) == center)
        var layout = center
        layout.pins = ["code": 0]
        // Emptying the column a pin is in moves the pin next door.
        let widened = layout.settingRows(1, inColumn: 2).settingRows(0, inColumn: 1)
        #expect(widened.rowCounts == [0, 0, 1])
        #expect(widened.pins == ["code": 0])
    }
}

@Suite struct LayoutTests {
    @Test func parsesRatios() {
        #expect(Layout.parse("20/60/20")?.ratios == [20, 60, 20])
        #expect(Layout.parse("1:2:1")?.ratios == [1, 2, 1])
        #expect(Layout.parse("50 50")?.ratios == [50, 50])
        #expect(Layout.parse("20/x/20") == nil)
        #expect(Layout.parse("0/100") == nil)
        #expect(Layout.parse("") == nil)
    }

    @Test func labelsAndFractions() {
        #expect(Layout(name: "Thirds", ratios: [33.33, 33.33, 33.33]).ratioLabel == "33/33/33")
        #expect(Layout(name: "x", ratios: [1, 3]).fractions == [0.25, 0.75])
    }

    @Test func pinnedOnlyLeavesOtherAppsAlone() throws {
        var layout = focus
        layout.pins = ["vscode": 1]
        #expect(layout.arranges(appID: "slack"))
        layout.pinnedOnly = true
        #expect(layout.arranges(appID: "vscode"))
        #expect(!layout.arranges(appID: "slack"))
        #expect(!layout.arranges(appID: nil))
        let decoded = try JSONDecoder().decode(Layout.self, from: JSONEncoder().encode(layout))
        #expect(decoded.pinnedOnly)
        #expect(try !String(decoding: JSONEncoder().encode(focus), as: UTF8.self).contains("pinnedOnly"))
    }

    @Test func addingAndRemovingColumnsKeepsPinsInPlace() {
        var layout = focus
        layout.pins = ["slack": 0, "vscode": 1, "claude": 2]

        let added = layout.addingColumn()
        #expect(added.ratios == [20, 30, 30, 20])
        #expect(added.pins == ["slack": 0, "vscode": 1, "claude": 3])

        let removed = layout.removingColumn(at: 1)
        #expect(removed.ratios == [80, 20])
        #expect(removed.pins == ["slack": 0, "vscode": 0, "claude": 1])

        #expect(layout.removingColumn(at: 0).ratios == [80, 20])
        #expect(Layout(name: "Full", ratios: [100]).removingColumn(at: 0).ratios == [100])
    }

    @Test func draggingAColumnEdgeSnapsAndOnlyTouchesNeighbours() {
        #expect(focus.resizedRatios(movingBoundary: 0, to: 0.33) == [35, 45, 20])
        #expect(focus.resizedRatios(movingBoundary: 1, to: 0.99) == [20, 75, 5])
        #expect(focus.resizedRatios(movingBoundary: 0, to: -1) == [5, 75, 20])
        #expect(focus.resizedRatios(movingBoundary: 2, to: 0.5) == [20, 60, 20])
    }
}

@Suite struct ShortcutTests {
    @Test func roundTripsThroughStrings() throws {
        let shortcut = try #require(Shortcut(string: "cmd+opt+ctrl+left"))
        #expect(shortcut.stringValue == "ctrl+opt+cmd+left")
        #expect(shortcut.displayString == "⌃⌥⌘←")
        #expect(Shortcut(string: "ctrl+opt+space")?.displayKeys == ["⌃", "⌥", "Space"])
        #expect(Shortcut(string: "ctrl+banana") == nil)
    }

    @Test func clearedShortcutsStayCleared() throws {
        var config = Config()
        config.moveLeftShortcut = nil
        config.launcherOnPrimaryDisplay = true
        config.accent = .system
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.moveLeftShortcut == nil)
        #expect(decoded.launcherOnPrimaryDisplay)
        #expect(decoded.accent == .system)
        #expect(decoded.moveRightShortcut == config.moveRightShortcut)

        let minimal = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(minimal == Config())

        let unknownAccent = try JSONDecoder().decode(Config.self, from: Data(#"{"accent": "rainbow"}"#.utf8))
        #expect(unknownAccent.accent == .omw)
    }
}

@Suite struct FuzzyTests {
    @Test func matchesWordsAndRatios() {
        #expect(Fuzzy.score("code layout", in: "Code 20/60/20 Layout") != nil)
        #expect(Fuzzy.score("20/60", in: "Code 20/60/20 Layout") != nil)
        #expect(Fuzzy.score("hlv", in: "Halves 50/50 Layout") != nil)
        #expect(Fuzzy.score("thirds", in: "Halves 50/50 Layout") == nil)
        #expect(Fuzzy.score("ha", in: "Halves")! > Fuzzy.score("lv", in: "Halves")!)
    }
}
