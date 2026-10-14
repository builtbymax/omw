import Foundation
import OMWCore
import ServiceManagement

/// Loads and saves ~/.config/omw/config.json. Every change is written right away.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet { if config != oldValue && !isReloading { save() } }
    }

    private var isReloading = false

    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/omw/config.json")

    init() {
        if let data = try? Data(contentsOf: url) {
            do {
                config = try JSONDecoder().decode(Config.self, from: data)
            } catch {
                // Keep the broken file around instead of silently overwriting the user's edits.
                NSLog("omw: could not read config, using defaults: \(error)")
                try? FileManager.default.removeItem(at: url.appendingPathExtension("broken"))
                try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("broken"))
                config = Config()
                save()
            }
        } else {
            config = Config()
            save()
        }
    }

    /// Re-reads the file after a manual edit. Throws on invalid JSON and keeps the current config,
    /// so the user can fix the file. The file isn't written back, to keep the user's formatting.
    func reload() throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            // The file was deleted: write the current config back instead of resetting to defaults.
            save()
            return
        }
        let loaded = try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
        isReloading = true
        config = loaded
        isReloading = false
    }

    func layout(id: UUID) -> Layout? {
        config.layouts.first { $0.id == id }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            NSLog("omw: could not save config: \(error)")
        }
    }
}

extension DecodingError {
    /// Short, readable reason for a config that fails to decode.
    var configMessage: String {
        func path(_ context: Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return keys.isEmpty ? "the file" : "\"\(keys.joined(separator: "."))\""
        }
        switch self {
        case .dataCorrupted(let context):
            let underlying = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            return underlying ?? context.debugDescription
        case .keyNotFound(let key, let context):
            return "Missing \"\(key.stringValue)\" in \(path(context))."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "Unexpected value at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return localizedDescription
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("omw: launch at login failed: \(error)")
        }
    }
}
