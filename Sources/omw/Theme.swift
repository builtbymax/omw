import AppKit
import OMWCore
import SwiftUI

/// omw's column layout, not SwiftUI's `Layout` protocol.
typealias Layout = OMWCore.Layout

/// Design tokens and building blocks for the glass look (see the "OMW" Figma file).
enum Theme {
    static let accentTop = Color(hex: 0x5AA5FF)
    static let accentBottom = Color(hex: 0x1F5FE0)
    static let tileTop = Color(hex: 0x4C9BFF)
    static let tileBottom = Color(hex: 0x1A56DB)
    static let accentText = Color(hex: 0x9CC6FF)
    static let green = Color(hex: 0x30D158)

    static var accent: LinearGradient {
        LinearGradient(colors: [accentTop, accentBottom], startPoint: .top, endPoint: .bottom)
    }

    /// The bright top edge that makes a surface read as glass.
    static func rim(_ top: Double = 0.28, _ bottom: Double = 0.06) -> LinearGradient {
        LinearGradient(colors: [.white.opacity(top), .white.opacity(bottom)], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

// MARK: - Surfaces

extension View {
    /// Liquid Glass on macOS 26+, a tinted material with a rim highlight before that.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self
                .background(shape.fill(.ultraThinMaterial))
                .background(shape.fill(tint ?? .clear))
                .overlay(shape.strokeBorder(Theme.rim(), lineWidth: 1))
        }
    }

    /// A grouped card: a faint fill with a rim, like the Settings sections.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(shape.fill(LinearGradient(colors: [.primary.opacity(0.07), .primary.opacity(0.04)],
                                                    startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Theme.rim(0.16, 0.04), lineWidth: 1))
    }

    /// Highlight for the selected row in lists.
    func selectedRow(_ selected: Bool, hovered: Bool = false, cornerRadius: CGFloat = 12) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(
            ZStack {
                if selected {
                    shape.fill(LinearGradient(colors: [.primary.opacity(0.14), .primary.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                    shape.strokeBorder(Theme.rim(0.22, 0.04), lineWidth: 1)
                } else if hovered {
                    shape.fill(.primary.opacity(0.06))
                }
            }
            .shadow(color: .black.opacity(selected ? 0.2 : 0), radius: 2, y: 1)
        )
    }
}

// MARK: - Icons

/// Blueprint tile with frosted white glass columns, the glyph for every layout.
struct LayoutIcon: View {
    let fractions: [Double]
    /// Rows per column, missing entries mean one row.
    var rows: [Int] = []
    var size: CGFloat = 28

    init(fractions: [Double], rows: [Int] = [], size: CGFloat = 28) {
        self.fractions = fractions
        self.rows = rows
        self.size = size
    }

    init(layout: Layout, size: CGFloat = 28) {
        self.init(fractions: layout.fractions, rows: layout.rowCounts, size: size)
    }

    var body: some View {
        let s = size / 64
        let pad = 9 * s, gap = 4 * s
        let tile = RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
        ZStack {
            tile.fill(LinearGradient(colors: [Theme.tileTop, Theme.tileBottom], startPoint: .top, endPoint: .bottom))
            tile.fill(RadialGradient(colors: [Color(hex: 0xBFE0FF, opacity: 0.45), .clear], center: .init(x: 0.5, y: 0.35),
                                     startRadius: 0, endRadius: size * 0.6))
            if size >= 24 { BlueprintGrid(divisions: 4).stroke(.white.opacity(0.1), lineWidth: 0.5) }
            GeometryReader { geometry in
                let available = geometry.size.width - pad * 2 - gap * CGFloat(fractions.count - 1)
                HStack(spacing: gap) {
                    ForEach(fractions.indices, id: \.self) { index in
                        VStack(spacing: gap) {
                            ForEach(0..<(rows.indices.contains(index) ? max(0, rows[index]) : 1), id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 5 * s, style: .continuous)
                                    .fill(LinearGradient(colors: [.white.opacity(0.95), Color(hex: 0xE6F0FF, opacity: 0.66)],
                                                         startPoint: .top, endPoint: .bottom))
                                    .overlay(RoundedRectangle(cornerRadius: 5 * s, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: max(0.5, 0.75 * s)))
                                    .shadow(color: Color(hex: 0x051F6B, opacity: 0.35), radius: 1.5 * s, y: 1.5 * s)
                            }
                        }
                        .frame(width: max(1, available * fractions[index]))
                        .frame(maxHeight: .infinity)
                    }
                }
                .padding(pad)
            }
            tile.strokeBorder(Theme.rim(0.55, 0.15), lineWidth: max(0.5, s))
        }
        .frame(width: size, height: size)
        .compositingGroup()
    }
}

struct BlueprintGrid: Shape {
    var divisions: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1..<divisions {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(divisions)
            let y = rect.minY + rect.height * CGFloat(i) / CGFloat(divisions)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// Colored glass tile with a white SF Symbol, like System Settings.
struct IconTile: View {
    enum Style {
        case general, layouts, shortcuts, windows, login, accessibility, config, move, moveVertical, display, spaces, about, search, quit, undo, update

        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .layouts: "rectangle.split.3x1.fill"
            case .shortcuts: "command"
            case .windows: "rectangle.split.2x1"
            case .login: "power"
            case .accessibility: "accessibility"
            case .config: "doc.text.fill"
            case .move: "arrow.left.arrow.right"
            case .moveVertical: "arrow.up.arrow.down"
            case .spaces: "square.on.square"
            case .display: "display"
            case .about: "info"
            case .search: "magnifyingglass"
            case .quit: "rectangle.portrait.and.arrow.right"
            case .undo: "arrow.uturn.backward"
            case .update: "arrow.down.circle.fill"
            }
        }

        var colors: (UInt32, UInt32) {
            switch self {
            case .general, .search: (0x8E9AAF, 0x5B6478)
            case .layouts: (0x4C9BFF, 0x1A56DB)
            case .shortcuts: (0xB57BFF, 0x7C3AED)
            case .windows: (0x3DD6C6, 0x0E9488)
            case .login: (0x5EE08A, 0x16A34A)
            case .accessibility: (0x5AC8FA, 0x0A84FF)
            case .config: (0xFFB257, 0xEA6A0C)
            case .move, .moveVertical: (0xFF7AA8, 0xDB2777)
            case .spaces: (0x3DD6C6, 0x0E9488)
            case .display: (0x7D8CFF, 0x4338CA)
            case .about: (0xA3AAB8, 0x6B7280)
            case .quit: (0xFF8A7A, 0xDC2626)
            case .undo: (0xFFD36E, 0xD97706)
            case .update: (0x4C9BFF, 0x1A56DB)
            }
        }
    }

    let style: Style
    var size: CGFloat = 26

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        ZStack {
            tile.fill(LinearGradient(colors: [Color(hex: style.colors.0), Color(hex: style.colors.1)], startPoint: .top, endPoint: .bottom))
            tile.fill(RadialGradient(colors: [.white.opacity(0.28), .clear], center: .init(x: 0.5, y: 0.1), startRadius: 0, endRadius: size * 0.8))
            Image(systemName: style.symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            tile.strokeBorder(Theme.rim(0.55, 0.15), lineWidth: 0.75)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
    }
}

// MARK: - Small controls

struct Keycap: View {
    let key: String
    /// Smaller keys for use inside chips.
    var compact = false

    init(_ key: String, compact: Bool = false) {
        self.key = key
        self.compact = compact
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 5 : 6, style: .continuous)
        Text(key)
            .font(.system(size: compact ? 10 : 11, weight: .medium))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, compact ? 4 : 6)
            .frame(minWidth: compact ? 17 : 22, minHeight: compact ? 17 : 22)
            .background(shape.fill(LinearGradient(colors: [.primary.opacity(0.16), .primary.opacity(0.07)], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(Theme.rim(0.3, 0.05), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
    }
}

struct Keycaps: View {
    let keys: [String]
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 2 : 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { Keycap($0.element, compact: compact) }
        }
    }
}

/// Monospaced "20/60/20" pill.
struct RatioPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.accentText)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.tileTop.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.tileTop.opacity(0.28)))
    }
}

/// Glowing dot + label, e.g. "Active" or "Granted".
struct StatusBadge: View {
    let text: String
    var color: Color = Theme.accentTop
    var textColor: Color = Theme.accentText

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).shadow(color: color.opacity(0.9), radius: 3)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(textColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(color.opacity(0.3)))
    }
}

/// Capsule glass buttons: primary is filled with the accent, the rest are clear glass.
/// Hovering brightens the fill and rim so it's clear they can be clicked.
struct GlassButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, destructive }

    var kind: Kind = .secondary
    var small = true

    func makeBody(configuration: Configuration) -> some View {
        GlassButton(configuration: configuration, kind: kind, small: small)
    }

    private struct GlassButton: View {
        let configuration: Configuration
        let kind: Kind
        let small: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false

        var body: some View {
            let shape = Capsule()
            let hover = hovered && isEnabled
            configuration.label
                .font(.system(size: small ? 12 : 13, weight: .semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, small ? 11 : 14)
                .padding(.vertical, small ? 4 : 7)
                .background {
                    switch kind {
                    case .primary:
                        shape.fill(Theme.accent)
                            .brightness(hover ? 0.08 : 0)
                            .shadow(color: Theme.accentBottom.opacity(hover ? 0.65 : 0.45), radius: hover ? 9 : 6, y: 2)
                    case .secondary: shape.fill(.primary.opacity(hover ? 0.17 : 0.1))
                    case .ghost: shape.fill(.primary.opacity(configuration.isPressed ? 0.12 : (hover ? 0.07 : 0)))
                    case .destructive: shape.fill(Color(hex: 0xFF453A, opacity: hover ? 0.28 : 0.16))
                    }
                }
                .overlay(kind == .ghost ? nil : shape.strokeBorder(Theme.rim(rim + (hover ? 0.2 : 0), 0.06), lineWidth: 1))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .brightness(configuration.isPressed ? -0.05 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hover)
                .contentShape(shape)
                .onHover { hovered = $0 }
        }

        private var rim: Double { kind == .primary ? 0.5 : 0.28 }

        private var foreground: Color {
            switch kind {
            case .primary: .white
            case .secondary: .primary
            case .ghost: .primary.opacity(hovered && isEnabled ? 0.9 : 0.7)
            case .destructive: Color(hex: 0xFF6B61)
            }
        }
    }
}

/// Plain buttons (icons, keycaps, chips) that grow a little and light up on hover.
struct HoverButtonStyle: ButtonStyle {
    var scale: CGFloat = 1.1

    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration, scale: scale)
    }

    private struct HoverButton: View {
        let configuration: Configuration
        let scale: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var colorScheme
        @State private var hovered = false

        var body: some View {
            let hover = hovered && isEnabled
            configuration.label
                .brightness(hover ? (colorScheme == .dark ? 0.12 : -0.08) : 0)
                .scaleEffect(configuration.isPressed ? 0.92 : (hover ? scale : 1))
                .animation(.spring(response: 0.2, dampingFraction: 0.65), value: hover)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
                .onHover { hovered = $0 }
        }
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    static var hoverable: HoverButtonStyle { HoverButtonStyle() }
    static func hoverable(scale: CGFloat) -> HoverButtonStyle { HoverButtonStyle(scale: scale) }
}

extension ButtonStyle where Self == GlassButtonStyle {
    static func glassCapsule(_ kind: GlassButtonStyle.Kind = .secondary, small: Bool = true) -> GlassButtonStyle {
        GlassButtonStyle(kind: kind, small: small)
    }
}

/// Uppercase section label above glass cards and list groups.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(.primary.opacity(0.42))
    }
}

/// The app's own icon, e.g. for the launcher footer and the About page.
struct AppIconView: View {
    var size: CGFloat = 26

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

/// App icon + name for a bundle identifier.
struct AppIdentity {
    let name: String
    let icon: NSImage?

    init(bundleID: String?) {
        let url = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        name = url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID ?? "Unknown"
        icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}
