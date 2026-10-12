import Foundation

public struct Config: Codable, Equatable {
    public var layouts: [Layout]
    /// Space in points around and between windows.
    public var gap: Double
    public var overlayShortcut: Shortcut?
    public var moveLeftShortcut: Shortcut?
    public var moveRightShortcut: Shortcut?
    public var lastLayoutID: UUID?

    public init(
        layouts: [Layout] = Layout.defaults,
        gap: Double = 8,
        overlayShortcut: Shortcut? = Shortcut(string: "ctrl+opt+space"),
        moveLeftShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+left"),
        moveRightShortcut: Shortcut? = Shortcut(string: "ctrl+opt+cmd+right"),
        lastLayoutID: UUID? = nil
    ) {
        self.layouts = layouts
        self.gap = gap
        self.overlayShortcut = overlayShortcut
        self.moveLeftShortcut = moveLeftShortcut
        self.moveRightShortcut = moveRightShortcut
        self.lastLayoutID = lastLayoutID
    }

    private enum CodingKeys: String, CodingKey {
        case layouts, gap, overlayShortcut, moveLeftShortcut, moveRightShortcut, lastLayoutID
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
        lastLayoutID = try c.decodeIfPresent(UUID.self, forKey: .lastLayoutID)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(layouts, forKey: .layouts)
        try c.encode(gap, forKey: .gap)
        try c.encode(overlayShortcut, forKey: .overlayShortcut)
        try c.encode(moveLeftShortcut, forKey: .moveLeftShortcut)
        try c.encode(moveRightShortcut, forKey: .moveRightShortcut)
        try c.encodeIfPresent(lastLayoutID, forKey: .lastLayoutID)
    }
}
