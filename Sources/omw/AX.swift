import AppKit
import ApplicationServices

/// Private but long-stable API (used by Rectangle, Amethyst, yabai) to map an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct ManagedWindow {
    let element: AXUIElement
    let app: AXUIElement
    let bundleID: String?
    let windowID: CGWindowID
    let frame: CGRect

    func with(frame: CGRect) -> ManagedWindow {
        ManagedWindow(element: element, app: app, bundleID: bundleID, windowID: windowID, frame: frame)
    }

    var pid: pid_t? {
        var pid: pid_t = 0
        return AXUIElementGetPid(app, &pid) == .success ? pid : nil
    }
}

/// Private but long-stable SkyLight calls (used by AltTab, yabai) to bring one specific window to the front.
/// Activating the app and raising the window through Accessibility isn't enough for Chromium-based apps like Dia:
/// activation brings back their previous window. Loaded at runtime, so omw still works if they're ever gone.
private enum SkyLight {
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private typealias ProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static let setFrontProcess = symbol("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                                                "_SLPSSetFrontProcessWithOptions", as: SetFrontProcess.self)
    private static let postEventRecord = symbol("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
                                                "SLPSPostEventRecordTo", as: PostEventRecord.self)
    /// Unavailable to Swift, but still in the system.
    private static let processForPID = symbol("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices",
                                              "GetProcessForPID", as: ProcessForPID.self)

    private static func symbol<T>(_ path: String, _ name: String, as type: T.Type) -> T? {
        guard let handle = dlopen(path, RTLD_LAZY), let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: type)
    }

    /// Makes `windowID` the key window of its app and the app the front one, as a click on the window would.
    static func focus(_ windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let setFrontProcess, let postEventRecord, let processForPID else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr, setFrontProcess(&psn, windowID, 0x200 /* user generated */) == .success else { return false }
        // The event record that makes a window key, as the window server sends it.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        for index in 0x20..<0x30 { bytes[index] = 0xff }
        for phase: UInt8 in [0x01, 0x02] {
            bytes[0x08] = phase
            _ = postEventRecord(&psn, &bytes)
        }
        return true
    }
}

/// Thin wrapper around the Accessibility API. All rects use top-left origin coordinates.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: Attributes

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let p = copy(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = copy(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
    }

    // MARK: Windows

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        return element(axApp, kAXFocusedWindowAttribute) ?? element(axApp, kAXMainWindowAttribute)
    }

    /// The focused window with everything needed to move it.
    static func focusedManagedWindow() -> ManagedWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let window = focusedWindow(), let id = windowID(of: window), let frame = frame(of: window) else { return nil }
        return ManagedWindow(element: window, app: AXUIElementCreateApplication(app.processIdentifier),
                             bundleID: app.bundleIdentifier, windowID: id, frame: frame)
    }

    /// The screen containing the center of `frame`.
    static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.axFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }

    /// The screen of the focused window, falling back to the screen under the mouse.
    static func targetScreen() -> NSScreen? {
        if let window = focusedWindow(), let frame = frame(of: window),
           let screen = NSScreen.screens.first(where: { $0.axFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    /// Normal windows on the current desktop (Space) whose center is on `screen` (any display for nil), frontmost first.
    static func visibleWindows(on screen: NSScreen?) -> [ManagedWindow] {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var zOrder: [CGWindowID: Int] = [:]
        var pids = Set<pid_t>()
        for (index, window) in info.enumerated() {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            zOrder[CGWindowID(number)] = index
            pids.insert(pid_t(pid))
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let screenFrame = screen?.axFrame
        var result: [ManagedWindow] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID && pids.contains(app.processIdentifier) {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows = copy(axApp, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows {
                guard let id = windowID(of: window), zOrder[id] != nil,
                      copy(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                      copy(window, kAXMinimizedAttribute) as? Bool != true,
                      copy(window, "AXFullScreen") as? Bool != true,
                      let frame = frame(of: window),
                      screenFrame?.contains(CGPoint(x: frame.midX, y: frame.midY)) ?? true else { continue }
                result.append(ManagedWindow(element: window, app: axApp, bundleID: app.bundleIdentifier, windowID: id, frame: frame))
            }
        }

        return result.sorted { zOrder[$0.windowID]! < zOrder[$1.windowID]! }
    }

    /// The frontmost normal window of another app under `point`, from the window server. Cheap enough for every click.
    static func windowUnder(_ point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        for window in info {
            guard let frame = bounds(of: window), frame.contains(point) else { continue }
            if let alpha = window[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            // omw's own panels (the stack dots, the column handles) catch the click themselves.
            if window[kCGWindowOwnerPID as String] as? Int == ownPID { return nil }
            // Menus, the Dock and other apps' overlays, often click-through, don't move with a drag.
            guard window[kCGWindowLayer as String] as? Int == 0 else { continue }
            guard let number = window[kCGWindowNumber as String] as? Int else { return nil }
            return (CGWindowID(number), frame)
        }
        return nil
    }

    /// A window's frame from the window server, without asking its app.
    static func serverFrame(of id: CGWindowID) -> CGRect? {
        (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first.flatMap(bounds(of:))
    }

    private static func bounds(of info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary)
    }

    /// Brings a window and its app to the front.
    @MainActor
    static func raise(_ window: ManagedWindow) {
        func raiseWindow() {
            AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
        if let pid = window.pid, SkyLight.focus(window.windowID, pid: pid) {
            raiseWindow()
            return
        }
        raiseWindow()
        AXUIElementSetAttributeValue(window.app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        // Activating the app can put its previous main window back on top, so raise again once that's done.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { raiseWindow() }
    }

    /// The Dock's icon strip as it is on screen right now, or nil when it hides itself.
    static func dockFrame() -> CGRect? {
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        if CFPreferencesGetAppBooleanValue("autohide" as CFString, "com.apple.dock" as CFString, nil) { return nil }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let children = copy(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute) as? [AXUIElement],
              let list = children.first(where: { copy($0, kAXRoleAttribute) as? String == kAXListRole }),
              let frame = frame(of: list), !frame.isEmpty else { return nil }
        return frame
    }

    static func hasEnhancedUI(_ window: ManagedWindow) -> Bool {
        copy(window.app, "AXEnhancedUserInterface") as? Bool == true
    }

    /// Fixed-size windows, like most settings windows, can't fill a cell.
    static func isResizable(_ window: ManagedWindow) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window.element, kAXSizeAttribute as CFString, &settable) == .success && settable.boolValue
    }

    static func setEnhancedUI(_ app: AXUIElement, _ on: Bool) {
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Position and size only, for in-between animation frames.
    static func setFrameFast(_ window: ManagedWindow, to rect: CGRect) {
        var origin = rect.origin
        var size = rect.size
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &origin)!)
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &size)!)
    }

    static func setFrame(_ window: ManagedWindow, to rect: CGRect) {
        let current = window.frame
        if abs(current.minX - rect.minX) < 1, abs(current.minY - rect.minY) < 1,
           abs(current.width - rect.width) < 1, abs(current.height - rect.height) < 1 { return }

        // Apps with "enhanced UI" (set by VoiceOver-like tools, Chrome/Electron) animate and drop
        // size changes, so it gets switched off while resizing.
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        let enhanced = hasEnhancedUI(window)
        if enhanced { AXUIElementSetAttributeValue(window.app, enhancedKey, kCFBooleanFalse) }

        var origin = rect.origin
        var size = rect.size
        let position = AXValueCreate(.cgPoint, &origin)!
        let dimensions = AXValueCreate(.cgSize, &size)!
        // Size, move, size again: the first resize can be clamped by the old position on screen.
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, dimensions)
        AXUIElementSetAttributeValue(window.element, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window.element, kAXSizeAttribute as CFString, dimensions)

        if enhanced { AXUIElementSetAttributeValue(window.app, enhancedKey, kCFBooleanTrue) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }

    /// Frame in top-left origin coordinates, as used by the Accessibility API.
    var axFrame: CGRect { Self.toAX(frame) }

    /// `visibleFrame` in top-left origin coordinates. AppKit caches it and doesn't always refresh it when
    /// the Dock changes (seen after display changes in a long-running omw), so windows ended up behind the Dock.
    /// When the cached value reaches into the live Dock, the side the Dock sits on is clamped to it.
    var axVisibleFrame: CGRect {
        var area = Self.toAX(visibleFrame)
        guard let dock = AX.dockFrame(), dock.intersects(axFrame) else { return area }
        if dock.width >= dock.height {
            if area.maxY > dock.midY { area.size.height = max(0, dock.minY - area.minY) }
        } else if dock.midX < axFrame.midX {
            if area.minX < dock.midX { area = CGRect(x: dock.maxX, y: area.minY, width: max(0, area.maxX - dock.maxX), height: area.height) }
        } else if area.maxX > dock.midX {
            area.size.width = max(0, dock.minX - area.minX)
        }
        return area
    }

    /// Displays as arranged in System Settings, left to right. The CLI numbers them in this order.
    static var leftToRight: [NSScreen] {
        screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// An Accessibility API rect in AppKit's bottom-left origin coordinates. Flipping is its own inverse.
    static func fromAX(_ rect: CGRect) -> NSRect { toAX(rect) }

    private static func toAX(_ rect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension NSScreen {
    /// The display's UUID, which stays the same across restarts unlike `displayID`. Workspaces remember displays by it.
    var uuid: String? {
        CGDisplayCreateUUIDFromDisplayID(displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
    }
}
