import CoreGraphics
import Foundation

/// A set of columns that split the screen horizontally, e.g. 20/60/20.
public struct Layout: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    /// Relative column widths. They don't need to add up to 100, they get normalized.
    public var ratios: [Double]
    /// Preferred column (0-based) per app bundle identifier.
    public var pins: [String: Int]
    public var shortcut: Shortcut?

    public init(id: UUID = UUID(), name: String, ratios: [Double], pins: [String: Int] = [:], shortcut: Shortcut? = nil) {
        self.id = id
        self.name = name
        self.ratios = ratios
        self.pins = pins
        self.shortcut = shortcut
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        ratios = try c.decode([Double].self, forKey: .ratios)
        pins = try c.decodeIfPresent([String: Int].self, forKey: .pins) ?? [:]
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut)
    }

    public var columnCount: Int { fractions.count }

    /// Normalized column widths that add up to 1. Invalid ratios fall back to a single column.
    public var fractions: [Double] {
        let valid = ratios.filter { $0 > 0 && $0.isFinite }
        let total = valid.reduce(0, +)
        guard !valid.isEmpty, total > 0 else { return [1] }
        return valid.map { $0 / total }
    }

    /// "20/60/20"
    public var ratioLabel: String {
        ratios.map { r in
            let rounded = r.rounded()
            return abs(r - rounded) < 0.5 ? String(Int(rounded)) : String(format: "%.1f", r)
        }.joined(separator: "/")
    }

    /// Parses "20/60/20", "20 60 20" or "1:2:1" into ratios.
    public static func parseRatios(_ text: String) -> [Double]? {
        let parts = text.split { "/ ,:|".contains($0) }
        let values = parts.compactMap { Double($0) }
        guard !values.isEmpty, values.count == parts.count, values.count <= 8, values.allSatisfy({ $0 > 0 }) else { return nil }
        return values
    }

    public static let defaults: [Layout] = [
        Layout(name: "Halves", ratios: [50, 50]),
        Layout(name: "Thirds", ratios: [33.33, 33.33, 33.33]),
        Layout(name: "Code", ratios: [20, 60, 20], pins: ["com.microsoft.VSCode": 1]),
        Layout(name: "Main Left", ratios: [70, 30]),
        Layout(name: "Main Right", ratios: [30, 70]),
        Layout(name: "Full", ratios: [100]),
    ]
}
