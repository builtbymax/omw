import Foundation

/// A global keyboard shortcut. Stored in the config as a readable string like "ctrl+opt+cmd+left".
public struct Shortcut: Hashable, Codable {
    /// Virtual key code (kVK_*).
    public var keyCode: UInt32
    /// Carbon modifier flags.
    public var modifiers: UInt32

    public static let command: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static let modifierNames: [(name: String, flag: UInt32, symbol: String)] = [
        ("ctrl", control, "⌃"),
        ("opt", option, "⌥"),
        ("shift", shift, "⇧"),
        ("cmd", command, "⌘"),
    ]

    private static let modifierAliases: [String: UInt32] = [
        "ctrl": control, "control": control,
        "opt": option, "option": option, "alt": option,
        "shift": shift,
        "cmd": command, "command": command,
    ]

    public static let keyNames: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
        "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
        "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
        "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
        "delete": 51, "escape": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "home": 115, "pageup": 116, "forwarddelete": 117, "end": 119, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]

    private static let keySymbols: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓",
        "return": "↩", "tab": "⇥", "space": "Space", "delete": "⌫", "escape": "⎋",
        "forwarddelete": "⌦", "home": "↖", "end": "↘", "pageup": "⇞", "pagedown": "⇟",
    ]

    public var keyName: String? {
        Self.keyNames.first { $0.value == keyCode }?.key
    }

    public var isFunctionKey: Bool {
        keyName?.hasPrefix("f") == true && keyName!.count > 1
    }

    public init?(string: String) {
        var modifiers: UInt32 = 0
        var key: UInt32?
        for part in string.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let flag = Self.modifierAliases[part] {
                modifiers |= flag
            } else if key == nil, let code = Self.keyNames[part] {
                key = code
            } else {
                return nil
            }
        }
        guard let key else { return nil }
        self.init(keyCode: key, modifiers: modifiers)
    }

    /// "ctrl+opt+cmd+left"
    public var stringValue: String {
        let mods = Self.modifierNames.filter { modifiers & $0.flag != 0 }.map(\.name)
        return (mods + [keyName ?? "key\(keyCode)"]).joined(separator: "+")
    }

    /// ["⌃", "⌥", "⌘", "←"]
    public var displayKeys: [String] {
        let mods = Self.modifierNames.filter { modifiers & $0.flag != 0 }.map(\.symbol)
        let name = keyName ?? "?"
        return mods + [Self.keySymbols[name] ?? name.uppercased()]
    }

    /// "⌃⌥⌘←"
    public var displayString: String { displayKeys.joined() }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let shortcut = Shortcut(string: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid shortcut \"\(string)\"")
        }
        self = shortcut
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }
}
