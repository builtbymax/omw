import AppKit
import Carbon.HIToolbox
import OMWCore

/// Global shortcuts via Carbon's RegisterEventHotKey, which needs no extra permissions.
final class HotkeyCenter: ObservableObject {
    static let shared = HotkeyCenter()

    /// Shortcuts another app already owns.
    @Published private(set) var failed: Set<Shortcut> = []
    /// Called to register everything again after `resume()`.
    var reload: (() -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var handlerInstalled = false
    private var suspended = false

    func register(_ shortcut: Shortcut, action: @escaping () -> Void) {
        guard !suspended else { return }
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x6F6D_7721), id: id) // "omw!"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs.append(ref)
            actions[id] = action
        } else {
            failed.insert(shortcut)
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        failed = []
    }

    /// Frees all shortcuts, e.g. while recording a new one.
    func suspend() {
        suspended = true
        unregisterAll()
    }

    func resume() {
        suspended = false
        reload?()
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { HotkeyCenter.shared.fire(hotKeyID.id) }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

extension Shortcut {
    /// Builds a shortcut from a recorded key press. Requires a modifier, except for F-keys.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= Shortcut.command }
        if flags.contains(.shift) { modifiers |= Shortcut.shift }
        if flags.contains(.option) { modifiers |= Shortcut.option }
        if flags.contains(.control) { modifiers |= Shortcut.control }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard shortcut.keyName != nil, modifiers != 0 || shortcut.isFunctionKey else { return nil }
        self = shortcut
    }
}
