// Checks Sparkle's EdDSA signatures against the public key the app ships with, independently of Sparkle:
//   swift scripts/verify-sparkle.swift <SUPublicEDKey> <appcast.xml> <archive.zip>
// The appcast has to carry a feed signature (SURequireSignedFeed), and its enclosure for the archive's
// file name a valid signature and length for the archive.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("verify-sparkle: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 else { fail("usage: verify-sparkle.swift <public-key> <appcast.xml> <archive.zip>") }
let (keyText, appcastPath, archivePath) = (arguments[arguments.startIndex], arguments[arguments.startIndex + 1], arguments[arguments.startIndex + 2])
guard let keyData = Data(base64Encoded: keyText), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
    fail("not an EdDSA public key: \(keyText)")
}
guard let appcast = FileManager.default.contents(atPath: appcastPath), let feed = String(data: appcast, encoding: .utf8) else {
    fail("can't read \(appcastPath)")
}
guard let archive = FileManager.default.contents(atPath: archivePath) else { fail("can't read \(archivePath)") }

func match(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    return (1..<result.numberOfRanges).map { String(text[Range(result.range(at: $0), in: text)!]) }
}

// The feed signature trails the XML and covers its first `length` bytes.
guard let trailer = match(#"<!-- sparkle-signatures:\s*edSignature: (\S+)\s*length: (\d+)\s*-->\s*$"#, in: feed),
      let feedSignature = Data(base64Encoded: trailer[0]), let feedLength = Int(trailer[1]), feedLength <= appcast.count else {
    fail("\(appcastPath) has no feed signature")
}
guard key.isValidSignature(feedSignature, for: appcast.prefix(feedLength)) else { fail("the feed signature of \(appcastPath) is invalid") }

let name = NSRegularExpression.escapedPattern(for: (archivePath as NSString).lastPathComponent)
guard let enclosure = match(#"<enclosure url="[^"]*/"# + name + #""([^>]*)>"#, in: feed),
      let length = match(#"length="(\d+)""#, in: enclosure[0]).flatMap({ Int($0[0]) }),
      let signature = match(#"sparkle:edSignature="([^"]+)""#, in: enclosure[0]).flatMap({ Data(base64Encoded: $0[0]) }) else {
    fail("\(appcastPath) has no signed enclosure for \(name)")
}
guard length == archive.count else { fail("the appcast says \(length) bytes, \(archivePath) has \(archive.count)") }
guard key.isValidSignature(signature, for: archive) else { fail("the signature of \(archivePath) is invalid") }
print("Feed and archive signatures are valid.")
