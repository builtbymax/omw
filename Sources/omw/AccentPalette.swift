import AppKit
import Observation
import OMWCore
import SwiftUI

/// The accent colors behind `Theme`: omw blue, or shades of the macOS accent color.
/// Observable, so every view that reads a `Theme` accent redraws when it changes.
@MainActor
@Observable
final class AccentPalette {
    static let shared = AccentPalette()

    var mode: Accent = .omw {
        didSet { if mode != oldValue { update() } }
    }

    private(set) var top = Color(hex: 0x5AA5FF)
    private(set) var bottom = Color(hex: 0x1F5FE0)
    private(set) var tileTop = Theme.brandTileTop
    private(set) var tileBottom = Theme.brandTileBottom
    private(set) var text = AccentPalette.adaptive(dark: NSColor(Theme.brandText), light: NSColor(Theme.brandTileBottom))
    private(set) var onAccent = Color.white
    /// The macOS accent color as it looks in dark mode, nil for Multicolor.
    private(set) var systemColor: Color?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let refresh: @Sendable (Notification) -> Void = { _ in Task { @MainActor in AccentPalette.shared.update() } }
        observers.append(NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification,
                                                                object: nil, queue: .main, using: refresh))
        // Posted right when the accent changes in System Settings, sometimes before the one above.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleColorPreferencesChangedNotification"), object: nil, queue: .main, using: refresh))
        update()
    }

    private func update() {
        let system = Self.systemAccent()
        systemColor = system.map { Color(nsColor: $0) }
        // Multicolor reports plain blue, which would look like a broken omw blue, so it keeps the original.
        guard mode == .system, let base = system else {
            top = Color(hex: 0x5AA5FF)
            bottom = Color(hex: 0x1F5FE0)
            tileTop = Theme.brandTileTop
            tileBottom = Theme.brandTileBottom
            text = Self.adaptive(dark: NSColor(Theme.brandText), light: NSColor(Theme.brandTileBottom))
            onAccent = .white
            return
        }
        // Lighter at the top and darker at the bottom, like the omw blue gradient.
        top = Color(nsColor: base.mixed(0.22, with: .white))
        bottom = Color(nsColor: base.mixed(0.25, with: .black))
        tileTop = Color(nsColor: base.mixed(0.12, with: .white))
        tileBottom = Color(nsColor: base.mixed(0.32, with: .black))
        text = Self.adaptive(dark: base.mixed(0.5, with: .white), light: base.mixed(0.5, with: .black))
        // White text stops being readable on light accents such as yellow.
        onAccent = base.luminance > 0.55 ? Color(hex: 0x1C1C1E) : .white
    }

    private static func systemAccent() -> NSColor? {
        guard UserDefaults.standard.object(forKey: "AppleAccentColor") != nil else { return nil }
        var color: NSColor?
        // The launcher and HUD are always dark, so the dark variant is the base for every shade.
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            color = NSColor.controlAccentColor.usingColorSpace(.sRGB)
        }
        return color
    }

    private static func adaptive(dark: NSColor, light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

private extension NSColor {
    func mixed(_ fraction: CGFloat, with other: NSColor) -> NSColor {
        blended(withFraction: fraction, of: other) ?? self
    }

    /// Relative luminance as in WCAG, 0 for black and 1 for white.
    var luminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0 }
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
}
