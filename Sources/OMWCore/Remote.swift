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
      move left|right|up|down [--no-swap]        Move the focused window to the neighbouring cell
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

extension RemoteCommand {
    /// The 0-based index for a display number from `omw displays`, nil when there's no such display.
    /// Checked before subtracting, which would overflow for Int.min.
    public static func displayIndex(number: Int, count: Int) -> Int? {
        number >= 1 && number <= count ? number - 1 : nil
    }
}

/// The window commands, as the CLI names them.
public enum WindowMove: String, Codable, CaseIterable, Sendable {
    case left, right, up, down
    case leftNoSwap, rightNoSwap, upNoSwap, downNoSwap
    case nextDisplay, previousDisplay
    case nextSpace, previousSpace

    static func parse(_ arguments: [String]) throws -> WindowMove {
        switch arguments {
        case ["left"]: .left
        case ["right"]: .right
        case ["up"]: .up
        case ["down"]: .down
        case ["left", "--no-swap"], ["--no-swap", "left"]: .leftNoSwap
        case ["right", "--no-swap"], ["--no-swap", "right"]: .rightNoSwap
        case ["up", "--no-swap"], ["--no-swap", "up"]: .upNoSwap
        case ["down", "--no-swap"], ["--no-swap", "down"]: .downNoSwap
        case ["--display", "next"]: .nextDisplay
        case ["--display", "previous"]: .previousDisplay
        case ["--space", "next"]: .nextSpace
        case ["--space", "previous"]: .previousSpace
        default: throw UsageError("Try: omw move left|right|up|down [--no-swap], omw move --display next|previous or omw move --space next|previous")
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

/// A Unix socket in Application Support. The CLI writes one JSON command and closes its writing side,
/// which ends the request. The app answers with one JSON response and closes the connection.
///
/// Only this user can connect (mode 0600), and the app trusts whatever does: any process of the user
/// can already control omw through Accessibility or just quit it, so the CLI isn't authenticated.
public enum RemoteSocket {
    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/omw/omw.sock").path
    }

    /// Commands are a few hundred bytes, anything bigger is rejected.
    public static let maxRequestSize = 64 << 10
    /// Answers list every layout or display, so they get more room.
    static let maxResponseSize = 1 << 20

    /// Sends a command to the app and waits at most `timeout` for its answer.
    public static func request(_ command: RemoteCommand, at path: String = defaultPath, timeout: TimeInterval = 15) throws -> RemoteResponse {
        guard var address = address(for: path) else { throw RemoteError.failed("Socket path is too long: \(path)") }
        let deadline = DispatchTime.now() + timeout
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw RemoteError.failed("Could not create a socket.") }
        defer { close(fd) }
        guard configure(fd, sendTimeout: timeout) else { throw RemoteError.failed("Could not set up the socket: \(String(cString: strerror(errno)))") }
        let connected = withSockaddr(&address) { connect(fd, $0, $1) }
        guard connected == 0 else {
            throw [ENOENT, ECONNREFUSED].contains(errno) ? RemoteError.notRunning : RemoteError.failed(String(cString: strerror(errno)))
        }
        let request = try JSONEncoder().encode(command)
        guard writeAll(fd, request) else { throw RemoteError.failed("Could not send the command to omw.") }
        shutdown(fd, SHUT_WR)
        let data: Data
        switch readAll(fd, limit: maxResponseSize, until: deadline) {
        case let .complete(complete): data = complete
        case .timedOut: throw RemoteError.failed("omw didn't answer in time.")
        case .tooLarge, .failed: throw RemoteError.failed("omw didn't answer.")
        }
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

    /// Reads one command from an accepted connection, answers it and closes the connection. The whole
    /// command has to arrive within `timeout`, so a client sending a byte now and then can't keep it open.
    public static func serve(_ client: Int32, timeout: TimeInterval = 5, handler: (RemoteCommand) -> RemoteResponse) {
        defer { close(client) }
        guard configure(client, sendTimeout: timeout) else { return }
        let response: RemoteResponse
        switch readAll(client, limit: maxRequestSize, until: .now() + timeout) {
        case let .complete(data):
            if let command = try? JSONDecoder().decode(RemoteCommand.self, from: data) {
                response = handler(command)
            } else {
                response = .failure("omw didn't understand the command. Are the CLI and the app the same version?")
            }
        case .tooLarge: response = .failure("The command is too large.")
        case .timedOut: response = .failure("The command didn't arrive in time.")
        case .failed: return
        }
        // The client may be gone by now, which is fine: the write just fails.
        if let data = try? JSONEncoder().encode(response) { _ = writeAll(client, data) }
    }

    /// Answers without reading the command, e.g. when too many clients are connected.
    static func reject(_ client: Int32, with response: RemoteResponse) {
        defer { close(client) }
        guard configure(client, sendTimeout: 1), let data = try? JSONEncoder().encode(response) else { return }
        _ = writeAll(client, data)
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

    /// Writes to a closed connection fail with EPIPE instead of raising SIGPIPE, which would kill the
    /// process, and give up after `sendTimeout`.
    private static func configure(_ fd: Int32, sendTimeout: TimeInterval) -> Bool {
        var on: Int32 = 1
        let seconds = sendTimeout.rounded(.down)
        var time = timeval(tv_sec: Int(seconds), tv_usec: Int32((sendTimeout - seconds) * 1_000_000))
        return setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) == 0
            && setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &time, socklen_t(MemoryLayout<timeval>.size)) == 0
    }

    private enum ReadResult {
        case complete(Data)
        case tooLarge, timedOut, failed
    }

    /// Reads until the other side closes its writing end. Fails past `limit` bytes or `deadline`,
    /// which counts for the whole message, not for each read.
    private static func readAll(_ fd: Int32, limit: Int, until deadline: DispatchTime) -> ReadResult {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let now = DispatchTime.now()
            guard now < deadline else { return .timedOut }
            let remaining = (deadline.uptimeNanoseconds - now.uptimeNanoseconds + 999_999) / 1_000_000
            var entry = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&entry, 1, Int32(clamping: remaining))
            if ready < 0 {
                if errno == EINTR { continue }
                return .failed
            }
            if ready == 0 { return .timedOut }
            let count = read(fd, &buffer, buffer.count)
            if count == 0 { return .complete(data) }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return .failed
            }
            guard data.count + count <= limit else { return .tooLarge }
            data.append(buffer, count: count)
        }
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }
}

/// Accepts connections on a socket from `RemoteSocket.listen` and serves each one on its own, so a slow
/// client doesn't hold up the others. Up to `maxClients` at a time, more get a "busy" answer right away.
public final class RemoteServer: @unchecked Sendable {
    private let listener: Int32
    private let timeout: TimeInterval
    private let slots: DispatchSemaphore
    private let handler: @Sendable (RemoteCommand) -> RemoteResponse
    private let clients = DispatchQueue(label: "omw.remote.clients", attributes: .concurrent)
    private var source: DispatchSourceRead?

    /// `handler` runs on a background queue, for several clients at once.
    public init(listener: Int32, maxClients: Int = 4, timeout: TimeInterval = 5,
                handler: @escaping @Sendable (RemoteCommand) -> RemoteResponse) {
        self.listener = listener
        self.timeout = timeout
        slots = DispatchSemaphore(value: maxClients)
        self.handler = handler
    }

    public func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: DispatchQueue(label: "omw.remote"))
        source.setEventHandler { [self] in acceptClient() }
        source.setCancelHandler { [listener] in close(listener) }
        source.resume()
        self.source = source
    }

    /// Stops accepting connections and closes the listening socket.
    public func stop() {
        source?.cancel()
        source = nil
    }

    private func acceptClient() {
        let client = accept(listener, nil, nil)
        guard client >= 0 else { return }
        guard slots.wait(timeout: .now()) == .success else {
            RemoteSocket.reject(client, with: .failure("omw is busy with other commands, try again."))
            return
        }
        clients.async { [self] in
            defer { slots.signal() }
            RemoteSocket.serve(client, timeout: timeout, handler: handler)
        }
    }
}
