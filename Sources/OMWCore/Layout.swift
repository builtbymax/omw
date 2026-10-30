import CoreGraphics
import Foundation

/// A set of columns that split the screen horizontally, e.g. 20/60/20. A column can be split into
/// equal rows, e.g. 2x20/60/2x20, or stay empty, e.g. _20/60/_20 for a centered window.
/// Every column/row combination is a cell, numbered column by column. Empty columns have no cells.
public struct Layout: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Relative column widths. They don't need to add up to 100, they get normalized.
    public var ratios: [Double]
    /// Number of rows per column, 0 for an empty column. Missing entries mean a single row.
    public var rows: [Int]
    /// Preferred cell (0-based, see `cells`) per app bundle identifier. Without rows, a cell is a column.
    public var pins: [String: Int]
    /// Only windows of pinned apps are moved, everything else stays where it is.
    public var pinnedOnly: Bool
    public var shortcut: Shortcut?

    public init(id: UUID = UUID(), name: String, ratios: [Double], rows: [Int] = [], pins: [String: Int] = [:],
                pinnedOnly: Bool = false, shortcut: Shortcut? = nil) {
        self.id = id
        self.name = name
        self.ratios = ratios
        self.rows = rows
        self.pins = pins
        self.pinnedOnly = pinnedOnly
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, ratios, rows, pins, pinnedOnly, shortcut
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        ratios = try c.decode([Double].self, forKey: .ratios)
        rows = try c.decodeIfPresent([Int].self, forKey: .rows) ?? []
        pins = try c.decodeIfPresent([String: Int].self, forKey: .pins) ?? [:]
        pinnedOnly = try c.decodeIfPresent(Bool.self, forKey: .pinnedOnly) ?? false
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        // The same rules as typed columns, so a hand-edited config can't hold what the launcher refuses.
        if let error = Self.check(ratios: ratios, rows: rows) {
            throw DecodingError.dataCorruptedError(forKey: .ratios, in: c, debugDescription: "Layout \u{201C}\(name)\u{201D}: \(error.message)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(ratios, forKey: .ratios)
        // Layouts without rows keep the config file as it was.
        if rowCounts.contains(where: { $0 != 1 }) { try c.encode(rowCounts, forKey: .rows) }
        try c.encode(pins, forKey: .pins)
        if pinnedOnly { try c.encode(pinnedOnly, forKey: .pinnedOnly) }
        try c.encodeIfPresent(shortcut, forKey: .shortcut)
    }

    public var columnCount: Int { fractions.count }

    /// Whether applying the layout moves windows of this app.
    public func arranges(appID: String?) -> Bool {
        !pinnedOnly || appID.map { pins[$0] != nil } ?? false
    }

    public static let maxRows = 4

    /// Rows of every column, between 0 (empty) and `maxRows`. At least one column is never empty.
    public var rowCounts: [Int] {
        let counts = (0..<columnCount).map { rows.indices.contains($0) ? min(max(rows[$0], 0), Self.maxRows) : 1 }
        return counts.contains { $0 > 0 } ? counts : counts.map { _ in 1 }
    }

    /// The column closest to `column` that isn't empty, preferring the left one on a tie.
    public func nearestFilledColumn(to column: Int) -> Int {
        let counts = rowCounts
        return counts.indices.filter { counts[$0] > 0 }.min { abs($0 - column) < abs($1 - column) } ?? 0
    }

    /// Column and row of every cell, top to bottom within a column, columns left to right.
    public var cells: [(column: Int, row: Int)] {
        rowCounts.enumerated().flatMap { column, count in (0..<count).map { (column, $0) } }
    }

    public var cellCount: Int { rowCounts.reduce(0, +) }

    public func cellIndex(column: Int, row: Int) -> Int {
        rowCounts.prefix(column).reduce(0, +) + row
    }

    /// The cell next to `cell` in a direction: dx moves between columns (to the row at the same height),
    /// dy between the rows of a column. Nil at the edge of the layout.
    public func neighbour(of cell: Int, dx: Int, dy: Int) -> Int? {
        let cells = cells, counts = rowCounts
        guard cells.indices.contains(cell) else { return nil }
        let (column, row) = cells[cell]
        if dx != 0 {
            var target = column + dx
            while counts.indices.contains(target), counts[target] == 0 { target += dx }
            guard counts.indices.contains(target) else { return nil }
            // Middle of the current row, as a fraction of the height. A tie goes to the upper row.
            let middle = (Double(row) + 0.5) / Double(counts[column])
            let targetRow = min(max(Int((middle * Double(counts[target])).rounded(.up)) - 1, 0), counts[target] - 1)
            return cellIndex(column: target, row: targetRow)
        }
        let target = row + dy
        guard (0..<counts[column]).contains(target) else { return nil }
        return cellIndex(column: column, row: target)
    }

    /// "Top", "Bottom", "Row 2"… for a cell in a column with rows, nil for full-height columns.
    public func rowName(of cell: Int) -> String? {
        guard cells.indices.contains(cell) else { return nil }
        let (column, row) = cells[cell]
        switch (rowCounts[column], row) {
        case (1, _): return nil
        case (_, 0): return "Top"
        case (let count, let row) where row == count - 1: return "Bottom"
        case (3, _): return "Middle"
        default: return "Row \(row + 1)"
        }
    }

    /// Same layout with different columns or rows. Pins follow their column through `columnMap`
    /// (old column → new column) and stay in their row as far as the new column has one.
    public func restructured(ratios newRatios: [Double], rows newRows: [Int], columnMap: (Int) -> Int = { $0 }) -> Layout {
        let oldCells = cells
        var copy = self
        copy.ratios = newRatios
        copy.rows = newRows
        let counts = copy.rowCounts
        copy.pins = pins.mapValues { cell in
            let (column, row) = oldCells.indices.contains(cell) ? oldCells[cell] : (cell, 0)
            let target = copy.nearestFilledColumn(to: min(max(columnMap(column), 0), counts.count - 1))
            return copy.cellIndex(column: target, row: min(row, counts[target] - 1))
        }
        return copy
    }

    /// Splits `column` into `count` rows, 0 empties it. The last column with windows can't be emptied.
    public func settingRows(_ count: Int, inColumn column: Int) -> Layout {
        var counts = rowCounts
        guard counts.indices.contains(column) else { return self }
        counts[column] = min(max(count, 0), Self.maxRows)
        guard counts.contains(where: { $0 > 0 }) else { return self }
        return restructured(ratios: ratios, rows: counts)
    }

    /// Whether `column` can be emptied, i.e. another column still takes windows.
    public func canEmpty(column: Int) -> Bool {
        rowCounts.enumerated().contains { $0.offset != column && $0.element > 0 }
    }

    /// Normalized column widths that add up to 1. Invalid ratios fall back to a single column.
    public var fractions: [Double] {
        let valid = ratios.filter { $0 > 0 && $0.isFinite }
        let total = valid.reduce(0, +)
        guard !valid.isEmpty, total > 0 else { return [1] }
        return valid.map { $0 / total }
    }

    /// "20/60/20", "2x20/60/2x20" with rows, "_20/60/_20" with empty columns.
    public var ratioLabel: String {
        let counts = rowCounts
        return ratios.enumerated().map { index, r in
            // Formatting instead of Int(_:), which traps for values outside Int's range.
            let rounded = r.rounded()
            let value = abs(r - rounded) < 0.5 ? String(format: "%.0f", rounded) : String(format: "%.1f", r)
            switch counts.indices.contains(index) ? counts[index] : 1 {
            case 0: return "_\(value)"
            case 1: return value
            case let count: return "\(count)x\(value)"
            }
        }.joined(separator: "/")
    }

    /// Percent ratios after dragging the edge between column `boundary` and `boundary + 1`
    /// to `position` (0…1 of the width). Snaps to `step` and keeps every column at least `step` wide.
    public func resizedRatios(movingBoundary boundary: Int, to position: Double, step: Double = 0.05) -> [Double] {
        var percents = fractions.map { $0 * 100 }
        guard percents.indices.contains(boundary + 1) else { return percents }
        let start = percents[..<boundary].reduce(0, +)
        let end = start + percents[boundary] + percents[boundary + 1]
        let snap = step * 100
        let edge = min(max((position * 100 / snap).rounded() * snap, start + snap), end - snap)
        percents[boundary] = edge - start
        percents[boundary + 1] = end - edge
        return percents.map { ($0 * 100).rounded() / 100 }
    }

    public static let maxColumns = 8

    /// Splits the widest column in two. Apps pinned to columns after it move along.
    public func addingColumn() -> Layout {
        var percents = fractions.map { $0 * 100 }
        guard percents.count < Self.maxColumns,
              let widest = percents.indices.max(by: { percents[$0] < percents[$1] }) else { return self }
        percents[widest] /= 2
        percents.insert(percents[widest], at: widest + 1)
        var counts = rowCounts
        counts.insert(1, at: widest + 1)
        return restructured(ratios: percents.map { ($0 * 100).rounded() / 100 }, rows: counts) { $0 > widest ? $0 + 1 : $0 }
    }

    /// Removes a column and gives its width to the neighbour on the left (or right, for the first one).
    /// Apps pinned to it go to that neighbour.
    public func removingColumn(at index: Int) -> Layout {
        var percents = fractions.map { $0 * 100 }
        guard percents.count > 1, percents.indices.contains(index) else { return self }
        let width = percents.remove(at: index)
        let neighbour = max(0, index - 1)
        percents[neighbour] += width
        var counts = rowCounts
        counts.remove(at: index)
        return restructured(ratios: percents.map { ($0 * 100).rounded() / 100 }, rows: counts) {
            $0 == index ? neighbour : ($0 > index ? $0 - 1 : $0)
        }
    }

    /// Parses "20/60/20", "20 60 20" or "1:2:1" into ratios, "2x20/60/2x20" into ratios with rows,
    /// and "_20/60/_20" with empty columns (0 rows).
    public static func parse(_ text: String) -> (ratios: [Double], rows: [Int])? {
        try? validate(text).get()
    }

    /// Like `parse`, but says what's wrong with the text.
    public static func validate(_ text: String) -> Result<(ratios: [Double], rows: [Int]), ColumnSpecError> {
        let normalized = text.replacingOccurrences(of: "\\s*[x×]\\s*", with: "x", options: [.regularExpression, .caseInsensitive])
        let parts = normalized.split { "/ ,:|".contains($0) }
        guard !parts.isEmpty else { return .failure(.empty) }
        guard parts.count <= maxColumns else { return .failure(.tooManyColumns) }
        var ratios: [Double] = [], rows: [Int] = []
        for part in parts {
            let column = String(part)
            let empty = part.hasPrefix("_")
            let pieces = part.dropFirst(empty ? 1 : 0).lowercased().split(separator: "x", omittingEmptySubsequences: false)
            guard pieces.count <= 2, let value = pieces.last.flatMap({ Double($0) }), value.isFinite else {
                return .failure(.invalidColumn(column))
            }
            if empty && pieces.count == 2 { return .failure(.rowsInEmptyColumn(column)) }
            guard let count = empty ? 0 : (pieces.count == 2 ? Int(pieces[0]) : 1) else {
                return .failure(.invalidColumn(column))
            }
            if let error = check(ratio: value, rows: count, column: column) { return .failure(error) }
            ratios.append(value)
            rows.append(count)
        }
        if let error = check(ratios: ratios, rows: rows) { return .failure(error) }
        return .success((ratios, rows.contains { $0 != 1 } ? rows : []))
    }

    /// Column widths above this are rejected. Big enough for pixel widths like 640/1280/640.
    public static let maxRatio = 100_000.0

    /// What's wrong with a layout's columns, for typed columns and config.json alike.
    /// Missing `rows` entries mean a single row, extra ones are ignored.
    public static func check(ratios: [Double], rows: [Int]) -> ColumnSpecError? {
        guard !ratios.isEmpty else { return .empty }
        guard ratios.count <= maxColumns else { return .tooManyColumns }
        let counts = ratios.indices.map { rows.indices.contains($0) ? rows[$0] : 1 }
        for (ratio, count) in zip(ratios, counts) {
            let column = "\(count == 0 ? "_" : count == 1 ? "" : "\(count)x")\(ratio.isFinite ? String(format: "%g", ratio) : "\(ratio)")"
            if let error = check(ratio: ratio, rows: count, column: column) { return error }
        }
        return counts.contains { $0 > 0 } ? nil : .noWindows
    }

    private static func check(ratio: Double, rows: Int, column: String) -> ColumnSpecError? {
        guard ratio.isFinite, rows >= 0 else { return .invalidColumn(column) }
        guard ratio > 0 else { return .zeroWidth(column) }
        guard ratio <= maxRatio else { return .tooWide(column) }
        guard rows <= maxRows else { return .tooManyRows(column) }
        return nil
    }

    /// The layout with the columns from `text`, pins following their column. Nil if the text isn't valid.
    /// Apply it once the whole text is typed: every intermediate state would remap the pins again.
    public func applying(columns text: String) -> Layout? {
        guard let parsed = Self.parse(text) else { return nil }
        let candidate = restructured(ratios: parsed.ratios, rows: parsed.rows)
        return candidate.ratios == ratios && candidate.rowCounts == rowCounts ? self : candidate
    }

    /// "25 / 50 / 25 %", the widths as they end up on screen. Nil when the ratios already are percentages.
    public var percentLabel: String? {
        let percents = fractions.map { $0 * 100 }
        guard percents.count == ratios.count,
              zip(percents, ratios).contains(where: { abs($0 - $1) >= 0.05 }) else { return nil }
        let values = percents.map { p in
            let rounded = (p * 10).rounded() / 10
            return String(format: rounded == rounded.rounded() ? "%.0f" : "%.1f", rounded)
        }
        return values.joined(separator: " / ") + " %"
    }

    public static let defaults: [Layout] = [
        Layout(name: "Halves", ratios: [50, 50], shortcut: Shortcut(string: "ctrl+opt+1")),
        Layout(name: "Thirds", ratios: [33.33, 33.33, 33.33], shortcut: Shortcut(string: "ctrl+opt+2")),
        Layout(name: "Code", ratios: [20, 60, 20], pins: ["com.microsoft.VSCode": 1], shortcut: Shortcut(string: "ctrl+opt+3")),
        Layout(name: "Main Left", ratios: [70, 30], shortcut: Shortcut(string: "ctrl+opt+4")),
        Layout(name: "Main Right", ratios: [30, 70], shortcut: Shortcut(string: "ctrl+opt+5")),
        Layout(name: "Full", ratios: [100]),
        Layout(name: "Center", ratios: [20, 60, 20], rows: [0, 1, 0]),
    ]
}

/// Why a column spec like "20/60/20" can't be used.
public enum ColumnSpecError: Error, Equatable {
    case empty
    case tooManyColumns
    case invalidColumn(String)
    case zeroWidth(String)
    case tooWide(String)
    case tooManyRows(String)
    case rowsInEmptyColumn(String)
    case noWindows

    public var message: String {
        switch self {
        case .empty: "Enter column widths, e.g. 50/50."
        case .tooManyColumns: "At most \(Layout.maxColumns) columns."
        case let .invalidColumn(column): "\u{201C}\(column)\u{201D} isn't a column. Use a width like 20, 2x20 or _20."
        case let .zeroWidth(column): "\u{201C}\(column)\u{201D} needs a width above 0."
        case let .tooWide(column): "\u{201C}\(column)\u{201D} is too wide, use widths up to \(Int(Layout.maxRatio))."
        case let .tooManyRows(column): "\u{201C}\(column)\u{201D}: a column has at most \(Layout.maxRows) rows."
        case let .rowsInEmptyColumn(column): "\u{201C}\(column)\u{201D}: an empty column can't have rows."
        case .noWindows: "At least one column needs to take windows."
        }
    }
}
