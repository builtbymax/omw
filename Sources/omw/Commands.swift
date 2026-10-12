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

/// Moves a window to the neighbouring Space. macOS has no public API for this, so it does what
/// a person would do: hold the window by its title bar and press the Mission Control shortcut
/// for switching Spaces (⌃← / ⌃→, System Settings → Keyboard → Shortcuts → Mission Control).
@MainActor
enum SpaceMover {
    static func move(_ window: ManagedWindow, by delta: Int) {
        // Just right of the traffic lights, near the top edge, so it's title bar and not a tab.
        let grab = CGPoint(x: window.frame.minX + 80, y: window.frame.minY + 8)
        let restore = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)

        func post(_ type: CGEventType) {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: grab, mouseButton: .left)?.post(tap: .cghidEventTap)
        }

        post(.mouseMoved)
        post(.leftMouseDown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let arrow: CGKeyCode = delta > 0 ? 124 : 123
            for down in [true, false] {
                let key = CGEvent(keyboardEventSource: source, virtualKey: arrow, keyDown: down)
                key?.flags = .maskControl
                key?.post(tap: .cghidEventTap)
            }
            // Keep holding until the Space switch animation has picked up the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                post(.leftMouseUp)
                if let restore { CGWarpMouseCursorPosition(restore) }
            }
        }
    }
}
