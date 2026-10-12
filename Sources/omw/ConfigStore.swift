import Foundation
import OMWCore
import ServiceManagement

/// Loads and saves ~/.config/omw/config.json. Every change is written right away.
@MainActor
final class ConfigStore: ObservableObject {
    @Published var config: Config {
        didSet { if config != oldValue { save() } }
    }

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
