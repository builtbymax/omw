import AppKit
import OMWCore

/// Everything omw can do to the focused window. Hotkeys, the launcher, the menu and Settings all
/// read from this list.
enum WindowCommand: String, CaseIterable, Identifiable {
    case moveLeft, moveRight, moveUp, moveDown
    case nextDisplay, previousDisplay
    case nextSpace, previousSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveLeft: "Move Window Left"
        case .moveRight: "Move Window Right"
        case .moveUp: "Move Window Up"
        case .moveDown: "Move Window Down"
        case .nextDisplay: "Move Window to Next Display"
        case .previousDisplay: "Move Window to Previous Display"
        case .nextSpace: "Move Window to Next Workspace"
        case .previousSpace: "Move Window to Previous Workspace"
        }
    }

    var detail: String {
        switch self {
        case .moveLeft: "Moves the focused window one column to the left and swaps it with the window there."
        case .moveRight: "Moves the focused window one column to the right and swaps it with the window there."
        case .moveUp: "Moves the focused window to the row above. In a column without rows it takes the top half, from the bottom half it goes back to full height."
        case .moveDown: "Moves the focused window to the row below. In a column without rows it takes the bottom half, from the top half it goes back to full height."
        case .nextDisplay: "Moves the focused window to the matching column on the display to the right."
        case .previousDisplay: "Moves the focused window to the matching column on the display to the left."
        case .nextSpace: "Moves the focused window to the desktop on the right. Uses the Mission Control shortcut \u{201C}Move right a space\u{201D} (⌃→)."
        case .previousSpace: "Moves the focused window to the desktop on the left. Uses the Mission Control shortcut \u{201C}Move left a space\u{201D} (⌃←)."
        }
    }

    var style: IconTile.Style {
        switch self {
        case .moveLeft, .moveRight: .move
        case .moveUp, .moveDown: .moveVertical
        case .nextDisplay, .previousDisplay: .display
        case .nextSpace, .previousSpace: .spaces
        }
    }

    /// Menu bar symbol.
    var symbol: String {
        switch self {
        case .moveLeft: "arrow.left"
        case .moveRight: "arrow.right"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .nextDisplay: "arrow.right.to.line"
        case .previousDisplay: "arrow.left.to.line"
        case .nextSpace: "rectangle.righthalf.inset.filled.arrow.right"
        case .previousSpace: "rectangle.lefthalf.inset.filled.arrow.left"
        }
    }

    var keyPath: WritableKeyPath<Config, Shortcut?> {
        switch self {
        case .moveLeft: \.moveLeftShortcut
        case .moveRight: \.moveRightShortcut
        case .moveUp: \.moveUpShortcut
        case .moveDown: \.moveDownShortcut
        case .nextDisplay: \.moveToNextDisplayShortcut
        case .previousDisplay: \.moveToPreviousDisplayShortcut
        case .nextSpace: \.moveToNextSpaceShortcut
        case .previousSpace: \.moveToPreviousSpaceShortcut
        }
    }
}

/// Private but long-stable SkyLight API (used by yabai, Amethyst): the Spaces of each display.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSCopyManagedDisplaySpaces") private func CGSCopyManagedDisplaySpaces(_ connection: Int32) -> CFArray

/// Moves a window to the neighbouring Space. macOS has no public API for this, so it does what
/// a person would do: drag the window by its title bar and press the Mission Control shortcut
/// for switching Spaces (System Settings → Keyboard → Shortcuts → Mission Control).
@MainActor
enum SpaceMover {
    private struct Shortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    /// Starts the move. Whether the Space really switched is only known later; then it just beeps.
    static func move(_ window: ManagedWindow, by delta: Int) -> ActionError? {
        guard hasSpace(beside: window, by: delta) != false else {
            NSSound.beep()
            return .noSpace
        }
        guard let shortcut = missionControlShortcut(right: delta > 0) else {
            NSSound.beep()
            return .spaceShortcutOff(right: delta > 0)
        }
        afterKeysReleased(until: .now + 1) { drag(window, with: shortcut) }
        return nil
    }

    /// Runs `action` once no key is held. The omw hotkey (⌃⌥⇧→) is usually still down when the
    /// command fires, and macOS ignores the Space shortcut while the real arrow key is pressed.
    private static func afterKeysReleased(until deadline: Date, _ action: @escaping @MainActor () -> Void) {
        let modifiers: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
        let held = !CGEventSource.flagsState(.hidSystemState).intersection(modifiers).isEmpty
            || (0..<128).contains { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) }
        guard held, Date.now < deadline else {
            action()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { afterKeysReleased(until: deadline, action) }
    }

    private static func drag(_ window: ManagedWindow, with shortcut: Shortcut) {
        let grab = grabPoint(for: window)
        let restore = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)

        // Explicit empty flags, in case a modifier is still held after the wait timed out.
        func post(_ type: CGEventType, at point: CGPoint) {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.post(tap: .cghidEventTap)
        }

        // Without a real drag, current macOS ignores the Space switch for the held window.
        var switched = false
        let observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { switched = true } }

        post(.mouseMoved, at: grab)
        post(.leftMouseDown, at: grab)
        post(.leftMouseDragged, at: CGPoint(x: grab.x + 1, y: grab.y))
        post(.leftMouseDragged, at: grab)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for down in [true, false] {
                let key = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down)
                key?.flags = shortcut.flags
                key?.post(tap: .cghidEventTap)
            }
            // Keep holding until the Space switch animation has picked up the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                post(.leftMouseUp, at: grab)
                if let restore { CGWarpMouseCursorPosition(restore) }
                // No Space change means there's no Space in that direction or the shortcut didn't fire.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NSWorkspace.shared.notificationCenter.removeObserver(observer)
                    if !switched { NSSound.beep() }
                }
            }
        }
    }

    /// Whether the window's display has a Space in that direction, nil when macOS doesn't say.
    /// Without this check the first and last Space look like the command is broken.
    private static func hasSpace(beside window: ManagedWindow, by delta: Int) -> Bool? {
        guard let screen = AX.screen(containing: window.frame),
              let uuid = CGDisplayCreateUUIDFromDisplayID(screen.displayID)?.takeRetainedValue(),
              let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]] else { return nil }
        let id = CFUUIDCreateString(nil, uuid) as String
        // With "Displays have separate Spaces" off there's one entry for all displays.
        guard let display = displays.count == 1 ? displays.first : displays.first(where: { $0["Display Identifier"] as? String == id }),
              let spaces = (display["Spaces"] as? [[String: Any]])?.compactMap({ $0["ManagedSpaceID"] as? Int }),
              let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
              let index = spaces.firstIndex(of: current) else { return nil }
        return spaces.indices.contains(index + delta)
    }

    /// Just right of the zoom button, so it's title bar and not a tab or toolbar item. Apps with
    /// custom title bars move the traffic lights, so ask for the button instead of guessing.
    private static func grabPoint(for window: ManagedWindow) -> CGPoint {
        if let zoom = AX.element(window.element, kAXZoomButtonAttribute), let button = AX.frame(of: zoom) {
            return CGPoint(x: button.maxX + 6, y: button.midY)
        }
        return CGPoint(x: window.frame.minX + 80, y: window.frame.minY + 8)
    }

    /// "Move left/right a space" as configured in System Settings, nil when it's turned off.
    /// Real arrow-key presses carry fn and macOS only matches the shortcut with it, but the stored
    /// modifiers don't always include it.
    private static func missionControlShortcut(right: Bool) -> Shortcut? {
        let fallback = Shortcut(keyCode: right ? 124 : 123, flags: [.maskControl, .maskSecondaryFn])
        guard let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = hotkeys[right ? "81" : "79"] as? [String: Any] else { return fallback }
        if let enabled = entry["enabled"] as? Bool, !enabled { return nil }
        guard let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int], parameters.count == 3 else { return fallback }
        let keyCode = CGKeyCode(parameters[1])
        var flags = CGEventFlags(rawValue: UInt64(parameters[2]))
        if (123...126).contains(keyCode) { flags.insert(.maskSecondaryFn) }
        return Shortcut(keyCode: keyCode, flags: flags)
    }
}
