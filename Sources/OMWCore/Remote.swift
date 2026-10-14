import Foundation

/// What the `omw` command-line tool asks the running app to do.
public enum RemoteCommand: Codable, Equatable, Sendable {
    /// A layout by name, ratios or id, like the launcher search. `display` is a name or a 1-based index.
    case apply(layout: String, display: String?)
    case move(WindowMove)
    case refresh
    case undo
    case layouts
    case displays
    case open
    case reload

    public static let usage = """
    Usage: omw <command>

    Commands:
      apply <layout> [--display <name|number>]   Apply a layout by name or ratios ("code", "20/60", "halves")
      move left|right|up|down                    Move the focused window to the neighbouring cell
      move --display next|previous               Move the focused window to another display
      move --space next|previous                 Move the focused window to another workspace
      refresh                                    Place windows opened since the layout was applied
      undo                                       Undo the last arrange
      layouts                                    List layouts
      displays                                   List displays with their numbers for --display
      open                                       Show the launcher
      reload                                     Re-read ~/.config/omw/config.json
      help                                       Show this help
    """

    /// Parses the arguments after `omw`. Throws a `UsageError` with a message for the user.
    public static func parse(_ arguments: [String]) throws -> RemoteCommand {
        guard let name = arguments.first else { throw UsageError("Missing command.") }
        let rest = Array(arguments.dropFirst())
        switch name {
        case "apply":
            var words: [String] = [], display: String?
            var index = 0
            while index < rest.count {
                if rest[index] == "--display" || rest[index] == "-d" {
                    guard index + 1 < rest.count else { throw UsageError("--display needs a display name or number.") }
                    display = rest[index + 1]
                    index += 2
                } else {
                    words.append(rest[index])
                    index += 1
                }
            }
            let layout = words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !layout.isEmpty else { throw UsageError("Which layout? Try: omw apply code") }
            return .apply(layout: layout, display: display)
        case "move":
            return .move(try WindowMove.parse(rest))
        case "refresh", "undo", "layouts", "displays", "open", "reload":
            guard rest.isEmpty else { throw UsageError("\(name) takes no arguments.") }
            switch name {
            case "refresh": return .refresh
            case "undo": return .undo
            case "layouts": return .layouts
            case "displays": return .displays
            case "open": return .open
            default: return .reload
            }
        default:
            throw UsageError("Unknown command \u{201C}\(name)\u{201D}.")
        }
    }
}

/// The window commands, as the CLI names them.
public enum WindowMove: String, Codable, CaseIterable, Sendable {
    case left, right, up, down
    case nextDisplay, previousDisplay
    case nextSpace, previousSpace

    static func parse(_ arguments: [String]) throws -> WindowMove {
        switch arguments {
        case ["left"]: .left
        case ["right"]: .right
        case ["up"]: .up
        case ["down"]: .down
        case ["--display", "next"]: .nextDisplay
        case ["--display", "previous"]: .previousDisplay
        case ["--space", "next"]: .nextSpace
        case ["--space", "previous"]: .previousSpace
        default: throw UsageError("Try: omw move left|right|up|down, omw move --display next|previous or omw move --space next|previous")
        }
    }
}

public struct UsageError: Error, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }
}

/// The app's answer: what to print, and whether the CLI exits with success.
public struct RemoteResponse: Codable, Equatable, Sendable {
    public var ok: Bool
    public var message: String

    public init(ok: Bool, message: String) {
        self.ok = ok
        self.message = message
    }

    public static func success(_ message: String) -> RemoteResponse { RemoteResponse(ok: true, message: message) }
    public static func failure(_ message: String) -> RemoteResponse { RemoteResponse(ok: false, message: message) }
}

extension Layout {
    /// The layout a CLI argument means: exact name, id, the same columns, then the best fuzzy match
    /// on name and ratios like the launcher.
    public static func find(_ query: String, in layouts: [Layout]) -> Layout? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let match = layouts.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) { return match }
        if let id = UUID(uuidString: trimmed), let match = layouts.first(where: { $0.id == id }) { return match }
        if let parsed = parse(trimmed) {
            let columns = Layout(name: "", ratios: parsed.ratios, rows: parsed.rows)
            if let match = layouts.first(where: { layout in
                layout.rowCounts == columns.rowCounts && zip(layout.fractions, columns.fractions).allSatisfy { abs($0 - $1) < 0.001 }
            }) { return match }
        }
        return layouts.enumerated()
            .compactMap { index, layout in Fuzzy.score(trimmed, in: "\(layout.name) \(layout.ratioLabel)").map { (layout, $0, index) } }
            .max { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }?.0
    }
}

public enum RemoteError: Error, Equatable {
    /// Nobody listens on the socket.
    case notRunning
    case failed(String)

    public var message: String {
        switch self {
        case .notRunning: "omw isn't running. Start it with: open -a omw"
        case let .failed(reason): reason
        }
    }
}

/// A Unix socket in Application Support: the CLI writes one JSON command, the app answers with one
/// JSON response and closes the connection.
public enum RemoteSocket {
    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/omw/omw.sock").path
    }

    /// Sends a command to the app and waits for its answer.
    public static func request(_ command: RemoteCommand, at path: String = defaultPath, timeout: TimeInterval = 15) throws -> RemoteResponse {
        guard var address = address(for: path) else { throw RemoteError.failed("Socket path is too long: \(path)") }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RemoteError.failed("Could not create a socket.") }
        defer { close(fd) }
        setTimeout(fd, timeout)
        let connected = withSockaddr(&address) { connect(fd, $0, $1) }
        guard connected == 0 else {
            throw [ENOENT, ECONNREFUSED].contains(errno) ? RemoteError.notRunning : RemoteError.failed(String(cString: strerror(errno)))
        }
        let request = try JSONEncoder().encode(command)
        guard writeAll(fd, request) else { throw RemoteError.failed("Could not send the command to omw.") }
        shutdown(fd, SHUT_WR)
        let data = readAll(fd)
        guard !data.isEmpty else { throw RemoteError.failed("omw didn't answer.") }
        guard let response = try? JSONDecoder().decode(RemoteResponse.self, from: data) else {
            throw RemoteError.failed("omw sent an answer the CLI doesn't understand. Are both the same version?")
        }
        return response
    }

    /// Creates the listening socket, replacing a stale one from an earlier run. Only this user can connect.
    public static func listen(at path: String = defaultPath) throws -> Int32 {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard var address = address(for: path) else { throw RemoteError.failed("Socket path is too long: \(path)") }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RemoteError.failed("Could not create a socket.") }
        guard withSockaddr(&address, { bind(fd, $0, $1) }) == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw RemoteError.failed("Could not listen on \(path): \(reason)")
        }
        return fd
    }

    /// Reads one command from an accepted connection, answers it and closes the connection.
    public static func serve(_ client: Int32, handler: (RemoteCommand) -> RemoteResponse) {
        defer { close(client) }
        setTimeout(client, 5)
        let response: RemoteResponse
        if let command = try? JSONDecoder().decode(RemoteCommand.self, from: readAll(client)) {
            response = handler(command)
        } else {
            response = .failure("omw didn't understand the command. Are the CLI and the app the same version?")
        }
        if let data = try? JSONEncoder().encode(response) { _ = writeAll(client, data) }
    }

    private static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }

    private static func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    private static func setTimeout(_ fd: Int32, _ seconds: TimeInterval) {
        var time = timeval(tv_sec: Int(seconds), tv_usec: 0)
        let size = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &time, size)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, size)
    }

    /// Reads until the other side closes, at most 1 MB.
    private static func readAll(_ fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count < 1 << 20 {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}
