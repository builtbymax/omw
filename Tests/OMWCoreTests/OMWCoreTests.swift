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

    @Test func moveSwapsWithTheFrontmostWindowInTheTargetColumn() {
        // index 0 is focused in column 1; column 0 has windows 1 (front) and 3.
        let assignment = [1, 0, 2, 0]
        #expect(Arranger.move(0, by: -1, in: assignment, columnCount: 3) == [0, 1, 2, 0])
        #expect(Arranger.move(0, by: 1, in: assignment, columnCount: 3) == [2, 0, 1, 0])
        #expect(Arranger.move(1, by: -1, in: assignment, columnCount: 3) == nil)
    }

    @Test func moveIntoEmptyColumn() {
        #expect(Arranger.move(0, by: 1, in: [0, 1], columnCount: 3) == [1, 0])
        #expect(Arranger.move(1, by: 1, in: [0, 1], columnCount: 3) == [0, 2])
    }
}

@Suite struct LayoutTests {
    @Test func parsesRatios() {
        #expect(Layout.parseRatios("20/60/20") == [20, 60, 20])
        #expect(Layout.parseRatios("1:2:1") == [1, 2, 1])
        #expect(Layout.parseRatios("50 50") == [50, 50])
        #expect(Layout.parseRatios("20/x/20") == nil)
        #expect(Layout.parseRatios("0/100") == nil)
        #expect(Layout.parseRatios("") == nil)
    }

    @Test func labelsAndFractions() {
        #expect(Layout(name: "Thirds", ratios: [33.33, 33.33, 33.33]).ratioLabel == "33/33/33")
        #expect(Layout(name: "x", ratios: [1, 3]).fractions == [0.25, 0.75])
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
        let decoded = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        #expect(decoded.moveLeftShortcut == nil)
        #expect(decoded.moveRightShortcut == config.moveRightShortcut)

        let minimal = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        #expect(minimal == Config())
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
