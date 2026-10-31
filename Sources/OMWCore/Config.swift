import Foundation

/// Color of buttons, badges and focus rings. The layout blueprint and icons always stay omw blue.
public enum Accent: String, Codable, CaseIterable, Sendable {
    case omw, system
}

/// The edge of a cell the stacked window dots sit at.
public enum StackIndicatorPosition: String, Codable, CaseIterable, Sendable {
    case top, bottom, left, right

    /// Left and right stack the dots vertically.
    public var isVertical: Bool { self == .left || self == .right }
}

/// A modifier key to hold, e.g. for resizing columns.
public enum ModifierKey: String, Codable, CaseIterable, Sendable {
    case command, option, control, shift

    public var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
}

public struct Config: Codable, Equatable {
    public var layouts: [Layout]
    /// Space in points around and between windows, 0 to `maxGap`.
    public var gap: Double
    public var overlayShortcut: Shortcut?
    public var moveLeftShortcut: Shortcut?
    public var moveRightShortcut: Shortcut?
    public var moveUpShortcut: Shortcut?
    public var moveDownShortcut: Shortcut?
    /// Like the moves above, but the window already in the target cell stays there.
    public var moveLeftNoSwapShortcut: Shortcut?
    public var moveRightNoSwapShortcut: Shortcut?
    public var moveUpNoSwapShortcut: Shortcut?
    public var moveDownNoSwapShortcut: Shortcut?
    public var moveToNextDisplayShortcut: Shortcut?
    public var moveToPreviousDisplayShortcut: Shortcut?
    public var moveToNextSpaceShortcut: Shortcut?
    public var moveToPreviousSpaceShortcut: Shortcut?
    /// Only active inside the launcher: switches the display a layout is applied to.
    public var switchDisplayShortcut: Shortcut?
    /// Glide windows into their columns instead of jumping.
    public var animate: Bool
    /// Show the "Arranged N windows" confirmation with Undo after applying a layout.
    public var showHUD: Bool
    /// Off hides the status item; Settings stay reachable via the launcher or by reopening omw.
    public var showMenuBarIcon: Bool
    /// Open the launcher panel on the primary display. Layouts still go to the focused window's display.
    public var launcherOnPrimaryDisplay: Bool
    /// Dragging a window drops it into the cell under the pointer.
    public var dragToSnap: Bool
    /// Holding `columnResizeKey` shows handles between the columns to resize them.
    public var columnResize: Bool
    public var columnResizeKey: ModifierKey
    /// Dots on cells with more than one window, to bring the ones behind to the front.
    public var showStackIndicator: Bool
    public var stackIndicatorPosition: StackIndicatorPosition
    public var accent: Accent
    public var lastLayoutID: UUID?

    public init(
        layouts: [Layout] = Layout.defaults,
        gap: Double = 8,
        overlayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+space"),
        moveLeftShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+left"),
        moveRightShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+right"),
        moveUpShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+up"),
        moveDownShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+down"),
        moveLeftNoSwapShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+cmd+left"),
        moveRightNoSwapShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+cmd+right"),
        moveUpNoSwapShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+cmd+up"),
        moveDownNoSwapShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+cmd+down"),
        moveToNextDisplayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+]"),
        moveToPreviousDisplayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+["),
        moveToNextSpaceShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+right"),
        moveToPreviousSpaceShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+left"),
        switchDisplayShortcut: Shortcut? = Shortcut(string: "cmd+d"),
        animate: Bool = true,
        showHUD: Bool = true,
        showMenuBarIcon: Bool = true,
        launcherOnPrimaryDisplay: Bool = false,
        dragToSnap: Bool = true,
        columnResize: Bool = true,
        columnResizeKey: ModifierKey = .command,
        showStackIndicator: Bool = true,
        stackIndicatorPosition: StackIndicatorPosition = .bottom,
        accent: Accent = .omw,
        lastLayoutID: UUID? = nil
    ) {
        self.layouts = layouts
        self.gap = gap
        self.overlayShortcut = overlayShortcut
        self.moveLeftShortcut = moveLeftShortcut
        self.moveRightShortcut = moveRightShortcut
        self.moveUpShortcut = moveUpShortcut
        self.moveDownShortcut = moveDownShortcut
        self.moveLeftNoSwapShortcut = moveLeftNoSwapShortcut
        self.moveRightNoSwapShortcut = moveRightNoSwapShortcut
        self.moveUpNoSwapShortcut = moveUpNoSwapShortcut
        self.moveDownNoSwapShortcut = moveDownNoSwapShortcut
        self.moveToNextDisplayShortcut = moveToNextDisplayShortcut
        self.moveToPreviousDisplayShortcut = moveToPreviousDisplayShortcut
        self.moveToNextSpaceShortcut = moveToNextSpaceShortcut
        self.moveToPreviousSpaceShortcut = moveToPreviousSpaceShortcut
        self.switchDisplayShortcut = switchDisplayShortcut
        self.animate = animate
        self.showHUD = showHUD
        self.showMenuBarIcon = showMenuBarIcon
        self.launcherOnPrimaryDisplay = launcherOnPrimaryDisplay
        self.dragToSnap = dragToSnap
        self.columnResize = columnResize
        self.columnResizeKey = columnResizeKey
        self.showStackIndicator = showStackIndicator
        self.stackIndicatorPosition = stackIndicatorPosition
        self.accent = accent
        self.lastLayoutID = lastLayoutID
    }

    public static let maxGap = 100.0

    private enum CodingKeys: String, CodingKey {
        case layouts, gap, overlayShortcut, moveLeftShortcut, moveRightShortcut, moveUpShortcut, moveDownShortcut
        case moveLeftNoSwapShortcut, moveRightNoSwapShortcut, moveUpNoSwapShortcut, moveDownNoSwapShortcut
        case moveToNextDisplayShortcut, moveToPreviousDisplayShortcut, moveToNextSpaceShortcut, moveToPreviousSpaceShortcut
        case switchDisplayShortcut, animate, showHUD, showMenuBarIcon, launcherOnPrimaryDisplay, dragToSnap, columnResize, columnResizeKey, showStackIndicator, stackIndicatorPosition
        case accent, lastLayoutID
    }

    /// Missing keys fall back to defaults, an explicit `null` shortcut stays disabled.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        func shortcut(_ key: CodingKeys, _ fallback: Shortcut?) throws -> Shortcut? {
            c.contains(key) ? try c.decodeIfPresent(Shortcut.self, forKey: key) : fallback
        }
        layouts = try c.decodeIfPresent([Layout].self, forKey: .layouts) ?? d.layouts
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? d.gap
        guard gap.isFinite, (0...Self.maxGap).contains(gap) else {
            throw DecodingError.dataCorruptedError(forKey: .gap, in: c, debugDescription: "\"gap\" needs to be between 0 and \(Int(Self.maxGap)).")
        }
        overlayShortcut = try shortcut(.overlayShortcut, d.overlayShortcut)
        moveLeftShortcut = try shortcut(.moveLeftShortcut, d.moveLeftShortcut)
        moveRightShortcut = try shortcut(.moveRightShortcut, d.moveRightShortcut)
        moveUpShortcut = try shortcut(.moveUpShortcut, d.moveUpShortcut)
        moveDownShortcut = try shortcut(.moveDownShortcut, d.moveDownShortcut)
        moveLeftNoSwapShortcut = try shortcut(.moveLeftNoSwapShortcut, d.moveLeftNoSwapShortcut)
        moveRightNoSwapShortcut = try shortcut(.moveRightNoSwapShortcut, d.moveRightNoSwapShortcut)
        moveUpNoSwapShortcut = try shortcut(.moveUpNoSwapShortcut, d.moveUpNoSwapShortcut)
        moveDownNoSwapShortcut = try shortcut(.moveDownNoSwapShortcut, d.moveDownNoSwapShortcut)
        moveToNextDisplayShortcut = try shortcut(.moveToNextDisplayShortcut, d.moveToNextDisplayShortcut)
        moveToPreviousDisplayShortcut = try shortcut(.moveToPreviousDisplayShortcut, d.moveToPreviousDisplayShortcut)
        moveToNextSpaceShortcut = try shortcut(.moveToNextSpaceShortcut, d.moveToNextSpaceShortcut)
        moveToPreviousSpaceShortcut = try shortcut(.moveToPreviousSpaceShortcut, d.moveToPreviousSpaceShortcut)
        switchDisplayShortcut = try shortcut(.switchDisplayShortcut, d.switchDisplayShortcut)
        animate = try c.decodeIfPresent(Bool.self, forKey: .animate) ?? d.animate
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        launcherOnPrimaryDisplay = try c.decodeIfPresent(Bool.self, forKey: .launcherOnPrimaryDisplay) ?? d.launcherOnPrimaryDisplay
        dragToSnap = try c.decodeIfPresent(Bool.self, forKey: .dragToSnap) ?? d.dragToSnap
        showStackIndicator = try c.decodeIfPresent(Bool.self, forKey: .showStackIndicator) ?? d.showStackIndicator
        // An unknown value from a newer omw falls back instead of failing the whole config.
        columnResize = try c.decodeIfPresent(Bool.self, forKey: .columnResize) ?? d.columnResize
        columnResizeKey = (try? c.decodeIfPresent(ModifierKey.self, forKey: .columnResizeKey)) ?? d.columnResizeKey
        stackIndicatorPosition = (try? c.decodeIfPresent(StackIndicatorPosition.self, forKey: .stackIndicatorPosition)) ?? d.stackIndicatorPosition
        accent = (try? c.decodeIfPresent(Accent.self, forKey: .accent)) ?? d.accent
        lastLayoutID = try c.decodeIfPresent(UUID.self, forKey: .lastLayoutID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layouts, forKey: .layouts)
        try c.encode(gap, forKey: .gap)
        try c.encode(overlayShortcut, forKey: .overlayShortcut)
        try c.encode(moveLeftShortcut, forKey: .moveLeftShortcut)
        try c.encode(moveRightShortcut, forKey: .moveRightShortcut)
        try c.encode(moveUpShortcut, forKey: .moveUpShortcut)
        try c.encode(moveDownShortcut, forKey: .moveDownShortcut)
        try c.encode(moveLeftNoSwapShortcut, forKey: .moveLeftNoSwapShortcut)
        try c.encode(moveRightNoSwapShortcut, forKey: .moveRightNoSwapShortcut)
        try c.encode(moveUpNoSwapShortcut, forKey: .moveUpNoSwapShortcut)
        try c.encode(moveDownNoSwapShortcut, forKey: .moveDownNoSwapShortcut)
        try c.encode(moveToNextDisplayShortcut, forKey: .moveToNextDisplayShortcut)
        try c.encode(moveToPreviousDisplayShortcut, forKey: .moveToPreviousDisplayShortcut)
        try c.encode(moveToNextSpaceShortcut, forKey: .moveToNextSpaceShortcut)
        try c.encode(moveToPreviousSpaceShortcut, forKey: .moveToPreviousSpaceShortcut)
        try c.encode(switchDisplayShortcut, forKey: .switchDisplayShortcut)
        try c.encode(animate, forKey: .animate)
        try c.encode(showHUD, forKey: .showHUD)
        try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try c.encode(launcherOnPrimaryDisplay, forKey: .launcherOnPrimaryDisplay)
        try c.encode(dragToSnap, forKey: .dragToSnap)
        try c.encode(columnResize, forKey: .columnResize)
        try c.encode(columnResizeKey, forKey: .columnResizeKey)
        try c.encode(showStackIndicator, forKey: .showStackIndicator)
        try c.encode(stackIndicatorPosition, forKey: .stackIndicatorPosition)
        try c.encode(accent, forKey: .accent)
        try c.encodeIfPresent(lastLayoutID, forKey: .lastLayoutID)
    }
}
