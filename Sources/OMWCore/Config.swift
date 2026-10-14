import Foundation

public struct Config: Codable, Equatable {
    public var layouts: [Layout]
    /// Space in points around and between windows.
    public var gap: Double
    public var overlayShortcut: Shortcut?
    public var moveLeftShortcut: Shortcut?
    public var moveRightShortcut: Shortcut?
    public var moveUpShortcut: Shortcut?
    public var moveDownShortcut: Shortcut?
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
    public var lastLayoutID: UUID?

    public init(
        layouts: [Layout] = Layout.defaults,
        gap: Double = 8,
        overlayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+space"),
        moveLeftShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+left"),
        moveRightShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+right"),
        moveUpShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+up"),
        moveDownShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+down"),
        moveToNextDisplayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+]"),
        moveToPreviousDisplayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+["),
        moveToNextSpaceShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+right"),
        moveToPreviousSpaceShortcut: Shortcut? = Shortcut(string: "ctrl+opt+shift+left"),
        switchDisplayShortcut: Shortcut? = Shortcut(string: "cmd+d"),
        animate: Bool = true,
        showHUD: Bool = true,
        showMenuBarIcon: Bool = true,
        launcherOnPrimaryDisplay: Bool = false,
        lastLayoutID: UUID? = nil
    ) {
        self.layouts = layouts
        self.gap = gap
        self.overlayShortcut = overlayShortcut
        self.moveLeftShortcut = moveLeftShortcut
        self.moveRightShortcut = moveRightShortcut
        self.moveUpShortcut = moveUpShortcut
        self.moveDownShortcut = moveDownShortcut
        self.moveToNextDisplayShortcut = moveToNextDisplayShortcut
        self.moveToPreviousDisplayShortcut = moveToPreviousDisplayShortcut
        self.moveToNextSpaceShortcut = moveToNextSpaceShortcut
        self.moveToPreviousSpaceShortcut = moveToPreviousSpaceShortcut
        self.switchDisplayShortcut = switchDisplayShortcut
        self.animate = animate
        self.showHUD = showHUD
        self.showMenuBarIcon = showMenuBarIcon
        self.launcherOnPrimaryDisplay = launcherOnPrimaryDisplay
        self.lastLayoutID = lastLayoutID
    }

    private enum CodingKeys: String, CodingKey {
        case layouts, gap, overlayShortcut, moveLeftShortcut, moveRightShortcut, moveUpShortcut, moveDownShortcut
        case moveToNextDisplayShortcut, moveToPreviousDisplayShortcut, moveToNextSpaceShortcut, moveToPreviousSpaceShortcut
        case switchDisplayShortcut, animate, showHUD, showMenuBarIcon, launcherOnPrimaryDisplay, lastLayoutID
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
        overlayShortcut = try shortcut(.overlayShortcut, d.overlayShortcut)
        moveLeftShortcut = try shortcut(.moveLeftShortcut, d.moveLeftShortcut)
        moveRightShortcut = try shortcut(.moveRightShortcut, d.moveRightShortcut)
        moveUpShortcut = try shortcut(.moveUpShortcut, d.moveUpShortcut)
        moveDownShortcut = try shortcut(.moveDownShortcut, d.moveDownShortcut)
        moveToNextDisplayShortcut = try shortcut(.moveToNextDisplayShortcut, d.moveToNextDisplayShortcut)
        moveToPreviousDisplayShortcut = try shortcut(.moveToPreviousDisplayShortcut, d.moveToPreviousDisplayShortcut)
        moveToNextSpaceShortcut = try shortcut(.moveToNextSpaceShortcut, d.moveToNextSpaceShortcut)
        moveToPreviousSpaceShortcut = try shortcut(.moveToPreviousSpaceShortcut, d.moveToPreviousSpaceShortcut)
        switchDisplayShortcut = try shortcut(.switchDisplayShortcut, d.switchDisplayShortcut)
        animate = try c.decodeIfPresent(Bool.self, forKey: .animate) ?? d.animate
        showHUD = try c.decodeIfPresent(Bool.self, forKey: .showHUD) ?? d.showHUD
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? d.showMenuBarIcon
        launcherOnPrimaryDisplay = try c.decodeIfPresent(Bool.self, forKey: .launcherOnPrimaryDisplay) ?? d.launcherOnPrimaryDisplay
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
        try c.encode(moveToNextDisplayShortcut, forKey: .moveToNextDisplayShortcut)
        try c.encode(moveToPreviousDisplayShortcut, forKey: .moveToPreviousDisplayShortcut)
        try c.encode(moveToNextSpaceShortcut, forKey: .moveToNextSpaceShortcut)
        try c.encode(moveToPreviousSpaceShortcut, forKey: .moveToPreviousSpaceShortcut)
        try c.encode(switchDisplayShortcut, forKey: .switchDisplayShortcut)
        try c.encode(animate, forKey: .animate)
        try c.encode(showHUD, forKey: .showHUD)
        try c.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try c.encode(launcherOnPrimaryDisplay, forKey: .launcherOnPrimaryDisplay)
        try c.encodeIfPresent(lastLayoutID, forKey: .lastLayoutID)
    }
}
