import Foundation
import OMWCore

/// `omw`: sends one command to the running app and prints its answer.
/// Exit codes: 0 done, 1 the command failed, 2 wrong usage, 3 omw isn't running.

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("omw: \(message)\n".utf8))
    exit(code)
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.isEmpty || ["help", "-h", "--help"].contains(arguments[0]) {
    print(RemoteCommand.usage)
    exit(arguments.isEmpty ? 2 : 0)
}

let command: RemoteCommand
do {
    command = try RemoteCommand.parse(arguments)
} catch let error as UsageError {
    fail("\(error.message)\n\n\(RemoteCommand.usage)", code: 2)
} catch {
    fail("\(error)", code: 2)
}

do {
    let response = try RemoteSocket.request(command)
    guard response.ok else { fail(response.message, code: 1) }
    if !response.message.isEmpty { print(response.message) }
} catch let error as RemoteError {
    fail(error.message, code: error == .notRunning ? 3 : 1)
} catch {
    fail("\(error)", code: 1)
}
