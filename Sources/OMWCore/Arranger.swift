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

/// Decides which column every window goes to. Windows are always passed front-to-back (z-order).
///
/// Every window gets the full height of its column. If there are more windows than columns,
/// the extra windows are layered into the same columns (Slack 20, VSCode 60, Claude 20, Spotify 20, …).
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

    /// Returns the column index for every window.
    ///
    /// 1. `pinned`: windows of apps with a preferred column go there.
    /// 2. Windows stay in the column they're already in, so re-applying a layout doesn't shuffle things.
    ///    With `balanced`, a column only keeps as many windows as an even split allows.
    /// 3. Everything else fills the column with the fewest windows, left to right.
    public static func assign(_ windows: [WindowSnapshot], layout: Layout, in area: CGRect, pinned: Bool, balanced: Bool) -> [Int] {
        let n = layout.columnCount
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
            let column = columnIndex(forX: window.frame.midX, layout: layout, in: area)
            if counts[column] < capacity { place(i, column) }
        }

        for i in windows.indices where result[i] == nil {
            let emptiest = counts.indices.min { counts[$0] < counts[$1] } ?? 0
            place(i, emptiest)
        }

        return result.map { $0 ?? 0 }
    }

    /// Moves the window at `index` one column over and swaps it with the frontmost window
    /// in the target column. Returns nil if there is no column in that direction.
    public static func move(_ index: Int, by delta: Int, in assignment: [Int], columnCount: Int) -> [Int]? {
        let from = assignment[index]
        let to = from + delta
        guard (0..<columnCount).contains(to) else { return nil }
        var next = assignment
        next[index] = to
        if let partner = assignment.indices.first(where: { $0 != index && assignment[$0] == to }) {
            next[partner] = from
        }
        return next
    }
}
