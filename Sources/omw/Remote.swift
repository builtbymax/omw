import AppKit
import OMWCore

/// Answers the `omw` command-line tool over the socket in Application Support.
@MainActor
final class RemoteController {
    private let store: ConfigStore
    private let manager: WindowManager
    private let overlay: OverlayController
    private var server: RemoteServer?

    init(store: ConfigStore, manager: WindowManager, overlay: OverlayController) {
        self.store = store
        self.manager = manager
        self.overlay = overlay
    }

    func start() {
        let listener: Int32
        do {
            listener = try RemoteSocket.listen()
        } catch {
            NSLog("omw: CLI unavailable: \((error as? RemoteError)?.message ?? "\(error)")")
            return
        }
        // Connections are read on background queues, commands run one at a time on the main thread.
        let server = RemoteServer(listener: listener) { [weak self] command in
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { self?.handle(command) ?? .failure("omw is quitting.") }
            }
        }
        server.start()
        self.server = server
    }

    func stop() {
        server?.stop()
        server = nil
        unlink(RemoteSocket.defaultPath)
    }

    func handle(_ command: RemoteCommand) -> RemoteResponse {
        switch command {
        case let .apply(query, display):
            guard let layout = Layout.find(query, in: store.config.layouts) else {
                return .failure("No layout matches \u{201C}\(query)\u{201D}. See: omw layouts")
            }
            var screen: NSScreen?
            if let display {
                screen = Self.screen(matching: display)
                guard screen != nil else { return .failure("No display matches \u{201C}\(display)\u{201D}. See: omw displays") }
            }
            switch manager.apply(layout, on: screen) {
            case let .success((count, screen)):
                let windows = count == 1 ? "1 window" : "\(count) windows"
                return .success("Applied \(layout.name) (\(layout.ratioLabel)) to \(windows) on \(screen.localizedName).")
            case let .failure(error):
                return .failure(error.message)
            }
        case let .move(move):
            return manager.perform(WindowCommand(move)).map { .failure($0.message) } ?? .success("")
        case .refresh:
            switch manager.refresh() {
            case let .success(count): return .success(count == 1 ? "Placed 1 new window." : "Placed \(count) new windows.")
            case let .failure(error): return .failure(error.message)
            }
        case .undo:
            return manager.undo().map { .failure($0.message) } ?? .success("Undid the last arrange.")
        case .layouts:
            return .success(layoutList())
        case .displays:
            return .success(displayList())
        case .open:
            overlay.show()
            return .success("")
        case .reload:
            do {
                try store.reload()
                return .success("Reloaded \(store.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).")
            } catch {
                return .failure("Could not reload the config, nothing changed: \(error.localizedDescription)")
            }
        }
    }

    /// A 1-based number from `omw displays`, or part of the display's name.
    private static func screen(matching query: String) -> NSScreen? {
        let screens = NSScreen.leftToRight
        if let number = Int(query) { return RemoteCommand.displayIndex(number: number, count: screens.count).map { screens[$0] } }
        return screens.first { $0.localizedName.localizedCaseInsensitiveContains(query) }
    }

    private func layoutList() -> String {
        let layouts = store.config.layouts
        let nameWidth = layouts.map(\.name.count).max() ?? 0
        let ratioWidth = layouts.map(\.ratioLabel.count).max() ?? 0
        return layouts.map { layout in
            [layout.name.padding(toLength: nameWidth, withPad: " ", startingAt: 0),
             layout.ratioLabel.padding(toLength: ratioWidth, withPad: " ", startingAt: 0),
             layout.id.uuidString].joined(separator: "  ")
        }.joined(separator: "\n")
    }

    private func displayList() -> String {
        NSScreen.leftToRight.enumerated().map { index, screen in
            "\(index + 1)  \(screen.localizedName)\(screen == NSScreen.screens.first ? " (primary)" : "")"
        }.joined(separator: "\n")
    }
}

private extension WindowCommand {
    init(_ move: WindowMove) {
        switch move {
        case .left: self = .moveLeft
        case .right: self = .moveRight
        case .up: self = .moveUp
        case .down: self = .moveDown
        case .leftNoSwap: self = .moveLeftNoSwap
        case .rightNoSwap: self = .moveRightNoSwap
        case .upNoSwap: self = .moveUpNoSwap
        case .downNoSwap: self = .moveDownNoSwap
        case .nextDisplay: self = .nextDisplay
        case .previousDisplay: self = .previousDisplay
        case .nextSpace: self = .nextSpace
        case .previousSpace: self = .previousSpace
        }
    }
}

/// Links the CLI bundled in omw.app into /usr/local/bin, asking for an admin password when needed.
/// A symlink, so Sparkle updates of the app update the CLI too.
@MainActor
enum CLIInstaller {
    enum Status: Equatable {
        /// Not inside omw.app, e.g. `swift run`.
        case unavailable
        case notInstalled
        case installed
        /// Links to the CLI of another copy of omw.
        case otherCopy
        /// Something else lives at the path.
        case taken
    }

    static let linkPath = "/usr/local/bin/omw"
    static var helperPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/omw").path }

    static var status: Status {
        let files = FileManager.default
        guard files.isExecutableFile(atPath: helperPath) else { return .unavailable }
        guard let destination = try? files.destinationOfSymbolicLink(atPath: linkPath) else {
            return files.fileExists(atPath: linkPath) ? .taken : .notInstalled
        }
        if destination == helperPath { return .installed }
        return destination.hasSuffix("/Contents/Helpers/omw") ? .otherCopy : .taken
    }

    static func install() throws {
        guard [.notInstalled, .otherCopy].contains(status) else { return }
        try run("mkdir -p /usr/local/bin && ln -sfn \(quoted(helperPath)) \(quoted(linkPath))")
    }

    static func uninstall() throws {
        guard [.installed, .otherCopy].contains(status) else { return }
        try run("rm -f \(quoted(linkPath))")
    }

    /// Runs the command directly, and with an admin prompt when /usr/local/bin isn't writable.
    private static func run(_ command: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 { return }

        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var error: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&error)
        if let error {
            // -128: the user cancelled the password prompt.
            if error[NSAppleScript.errorNumber] as? Int == -128 { throw CancellationError() }
            throw InstallError(message: error[NSAppleScript.errorMessage] as? String ?? "Unknown error")
        }
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
