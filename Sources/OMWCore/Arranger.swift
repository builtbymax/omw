import CoreGraphics

/// What the arranger needs to know about a window.
public struct WindowSnapshot: Equatable {
    public var appID: String?
    public var frame: CGRect

    public init(appID: String?, frame: CGRect) {
        self.appID = appID
        self.frame = frame
    }
}

/// Decides which cell every window goes to. Windows are always passed front-to-back (z-order).
///
/// Every window fills its cell, which is a whole column unless the column has rows. If there are more
/// windows than cells, the extra windows are layered into the same cells (Slack 20, VSCode 60, Claude 20, Spotify 20, …).
public enum Arranger {
    /// Column rectangles inside `area` (top-left origin coordinates), separated by `gap`.
    public static func columns(for layout: Layout, in area: CGRect, gap: Double) -> [CGRect] {
        let fractions = layout.fractions
        let g = CGFloat(max(0, gap))
        let usable = area.width - g * CGFloat(fractions.count + 1)
        var x = area.minX + g
        var rects: [CGRect] = []
        for (i, f) in fractions.enumerated() {
            let isLast = i == fractions.count - 1
            let width = isLast ? area.maxX - g - x : (usable * CGFloat(f)).rounded()
            rects.append(CGRect(x: x, y: area.minY + g, width: width, height: area.height - 2 * g))
            x += width + g
        }
        return rects
    }

    /// Cell rectangles (see `Layout.cells`): every column split into its rows, separated by `gap`.
    /// Empty columns have none.
    public static func cells(for layout: Layout, in area: CGRect, gap: Double) -> [CGRect] {
        let g = CGFloat(max(0, gap))
        return zip(columns(for: layout, in: area, gap: gap), layout.rowCounts).flatMap { column, count -> [CGRect] in
            guard count > 0 else { return [] }
            let height = ((column.height - g * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
            return (0..<count).map { row in
                let isLast = row == count - 1
                let y = column.minY + CGFloat(row) * (height + g)
                return CGRect(x: column.minX, y: y, width: column.width, height: isLast ? column.maxY - y : height)
            }
        }
    }

    /// The cell that contains `point`. In an empty column, the nearest cell next to it.
    public static func cellIndex(at point: CGPoint, layout: Layout, in area: CGRect) -> Int {
        let column = layout.nearestFilledColumn(to: columnIndex(forX: point.x, layout: layout, in: area))
        let count = layout.rowCounts[column]
        let position = area.height > 0 ? Double((point.y - area.minY) / area.height) : 0
        let row = min(max(Int(position * Double(count)), 0), count - 1)
        return layout.cellIndex(column: column, row: row)
    }

    /// The column whose horizontal span contains `x`.
    public static func columnIndex(forX x: CGFloat, layout: Layout, in area: CGRect) -> Int {
        let position = area.width > 0 ? Double((x - area.minX) / area.width) : 0
        var edge = 0.0
        let fractions = layout.fractions
        for (i, f) in fractions.enumerated() {
            edge += f
            if position < edge { return i }
        }
        return fractions.count - 1
    }

    /// Returns the cell index for every window.
    ///
    /// 1. `pinned`: windows of apps with a preferred cell go there.
    /// 2. Windows stay in the cell they're already in, so re-applying a layout doesn't shuffle things.
    ///    With `balanced`, a cell only keeps as many windows as an even split allows.
    /// 3. Everything else fills the cell with the fewest windows, left to right and top to bottom.
    public static func assign(_ windows: [WindowSnapshot], layout: Layout, in area: CGRect, pinned: Bool, balanced: Bool) -> [Int] {
        let n = layout.cellCount
        let capacity = balanced ? (windows.count + n - 1) / n : Int.max
        var result = [Int?](repeating: nil, count: windows.count)
        var counts = [Int](repeating: 0, count: n)

        func place(_ i: Int, _ column: Int) {
            result[i] = column
            counts[column] += 1
        }

        if pinned {
            for (i, window) in windows.enumerated() {
                if let app = window.appID, let column = layout.pins[app], (0..<n).contains(column) {
                    place(i, column)
                }
            }
        }

        for (i, window) in windows.enumerated() where result[i] == nil {
            let cell = cellIndex(at: CGPoint(x: window.frame.midX, y: window.frame.midY), layout: layout, in: area)
            if counts[cell] < capacity { place(i, cell) }
        }

        for i in windows.indices where result[i] == nil {
            let emptiest = counts.indices.min { counts[$0] < counts[$1] } ?? 0
            place(i, emptiest)
        }

        return result.map { $0 ?? 0 }
    }

    /// Where a window goes when it's moved up (-1) or down (+1) inside `column`: into the top or
    /// bottom half, or back to the full column if it already sits in the opposite half.
    public static func verticalSlot(for frame: CGRect, in column: CGRect, direction: Int, gap: Double) -> CGRect {
        let g = CGFloat(max(0, gap))
        let half = ((column.height - g) / 2).rounded(.down)
        let top = CGRect(x: column.minX, y: column.minY, width: column.width, height: half)
        let bottom = CGRect(x: column.minX, y: column.maxY - half, width: column.width, height: half)
        func matches(_ rect: CGRect) -> Bool {
            abs(frame.minX - rect.minX) < 2 && abs(frame.minY - rect.minY) < 2
                && abs(frame.width - rect.width) < 2 && abs(frame.height - rect.height) < 2
        }
        if direction < 0 { return matches(bottom) ? column : top }
        return matches(top) ? column : bottom
    }

    /// Moves the window at `index` one cell over (see `Layout.neighbour`) and swaps it with the frontmost
    /// window in the target cell. Returns nil if there is no cell in that direction.
    public static func move(_ index: Int, dx: Int, dy: Int, in assignment: [Int], layout: Layout) -> [Int]? {
        let from = assignment[index]
        guard let to = layout.neighbour(of: from, dx: dx, dy: dy) else { return nil }
        var next = assignment
        next[index] = to
        if let partner = assignment.indices.first(where: { $0 != index && assignment[$0] == to }) {
            next[partner] = from
        }
        return next
    }
}
