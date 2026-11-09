import Foundation

/// A saved arrangement of apps: per display, columns with apps pinned to their cells. Applying it
/// launches the pinned apps that aren't open and puts every pinned app in its cell. Other windows
/// stay where they are.
public struct Workspace: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// The displays the workspace covers, each with its own columns.
    public var displays: [WorkspaceDisplay]
    public var shortcut: Shortcut?

    public init(id: UUID = UUID(), name: String, displays: [WorkspaceDisplay] = [], shortcut: Shortcut? = nil) {
        self.id = id
        self.name = name
        self.displays = displays
        self.shortcut = shortcut
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, displays, shortcut
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        displays = try c.decodeIfPresent([WorkspaceDisplay].self, forKey: .displays) ?? []
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(displays, forKey: .displays)
        try c.encodeIfPresent(shortcut, forKey: .shortcut)
    }

    /// Bundle identifiers of every pinned app, display by display, column by column.
    public var apps: [String] {
        displays.flatMap { display in display.layout.pins.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key) }
    }

    /// The display and cell an app goes to. An app is pinned to one place only, but a hand-edited
    /// config can pin it twice: then the first display wins.
    public func placement(of appID: String?) -> (display: String, cell: Int)? {
        guard let appID else { return nil }
        for display in displays {
            if let cell = display.layout.pins[appID], (0..<display.layout.cellCount).contains(cell) {
                return (display.displayID, cell)
            }
        }
        return nil
    }

    /// The app pinned to `cell` on `displayID`, removed from wherever it was before.
    public func pinning(_ appID: String, display displayID: String, cell: Int) -> Workspace {
        var copy = unpinning(appID)
        guard let index = copy.displays.firstIndex(where: { $0.displayID == displayID }),
              (0..<copy.displays[index].layout.cellCount).contains(cell) else { return self }
        copy.displays[index].layout.pins[appID] = cell
        return copy
    }

    public func unpinning(_ appID: String) -> Workspace {
        var copy = self
        for index in copy.displays.indices { copy.displays[index].layout.pins[appID] = nil }
        return copy
    }
}

/// One display of a workspace.
public struct WorkspaceDisplay: Codable, Identifiable, Hashable {
    /// The display's UUID from CoreGraphics, which stays the same across restarts.
    public var displayID: String
    /// The display's name when it was added, shown while it isn't connected.
    public var displayName: String
    /// Columns and the apps pinned to them. Only windows of pinned apps are arranged.
    public var layout: Layout

    public var id: String { displayID }

    public init(displayID: String, displayName: String, layout: Layout) {
        self.displayID = displayID
        self.displayName = displayName
        self.layout = layout
        self.layout.pinnedOnly = true
    }

    private enum CodingKeys: String, CodingKey {
        case displayID = "display", displayName = "name", layout
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayID = try c.decode(String.self, forKey: .displayID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? "Display"
        layout = try c.decode(Layout.self, forKey: .layout)
        // Windows that aren't part of the workspace always stay floating.
        layout.pinnedOnly = true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayID, forKey: .displayID)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(layout, forKey: .layout)
    }
}
