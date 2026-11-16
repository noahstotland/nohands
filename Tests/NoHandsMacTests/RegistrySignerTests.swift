import Foundation
import CryptoKit
import Testing
@testable import NoHandsCore
@testable import NoHandsMac

private func temp() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nohands-signer-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
private let packBytes = Data(#"{"format":1,"id":"notes-extras","name":"Notes","version":"1.2.0","author":"","bundleIDs":["com.apple.Notes"],"commands":[{"phrases":["new note"],"actions":[{"kind":"press_key","key":"n","modifiers":["command"]}]}]}"#.utf8)
private func indexJSON(url: String = "https://packs.example.org/n.json", sha: String? = nil, extra: [String: Any] = [:]) -> Data {
    var entry: [String: Any] = ["id": "notes-extras", "name": "Notes", "author": "", "version": "1.2.0", "description": "", "bundleIDs": ["com.apple.Notes"],
                                "url": url, "sha256": sha ?? SHA256.hash(data: packBytes).map { String(format: "%02x", $0) }.joined()]
    entry.merge(extra) { $1 }
    return try! JSONSerialization.data(withJSONObject: ["format": 1, "serial": 3, "packs": [entry]] as [String: Any])
}

@Test func signedEnvelopeIsAcceptedOnlyUnderTheSigningKey() throws {
    let key = Curve25519.Signing.PrivateKey(), other = Curve25519.Signing.PrivateKey()
    let envelope = try RegistrySigner.sign(indexJSON: indexJSON(), privateKey: key.rawRepresentation)
    let index = try RegistryIndex.parse(envelope: envelope, trusting: [PackRegistry.TrustedKey(publicKey: key.publicKey.rawRepresentation)])
    #expect(index.serial == 3 && index.packs.map(\.id) == ["notes-extras"])
    #expect(throws: RegistryError.self) {
        try RegistryIndex.parse(envelope: envelope, trusting: [PackRegistry.TrustedKey(publicKey: other.publicKey.rawRepresentation)])
    }
    // A bad index is refused at signing time, naming the rule, not published.
    let bad: [(String, Data)] = [("http url", indexJSON(url: "http://packs.example.org/n.json")), ("bad hash", indexJSON(sha: "abc")),
                                 ("unknown key", indexJSON(extra: ["extra": 1])), ("not JSON", Data("{".utf8))]
    for (name, data) in bad {
        #expect(throws: RegistrySigner.SignerError.self, "\(name)") { try RegistrySigner.sign(indexJSON: data, privateKey: key.rawRepresentation) }
    }
    #expect(throws: RegistrySigner.SignerError.self) { try RegistrySigner.sign(indexJSON: indexJSON(), privateKey: Data(repeating: 1, count: 31)) }
}

@Test func keygenWritesAPrivateKeyAndNeverOverwritesOrFollowsALink() throws {
    let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("registry.key").path
    let made = try RegistrySigner.keygen(to: path)
    var info = stat()
    #expect(stat(path, &info) == 0 && info.st_mode & 0o777 == 0o600)
    let raw = try RegistrySigner.readPrivateKey(at: path)
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    #expect(made.publicKeyBase64 == key.publicKey.rawRepresentation.base64EncodedString() && made.keyID == PackRegistry.keyID(of: key.publicKey.rawRepresentation))
    let before = try Data(contentsOf: URL(fileURLWithPath: path))

    let target = dir.appendingPathComponent("target").path, link = dir.appendingPathComponent("link").path
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)   // dangling: a plain open would create the target
    for refused in [path, link] {
        #expect(throws: RegistrySigner.SignerError.self, "\(refused)") { try RegistrySigner.keygen(to: refused) }
    }
    #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before && !FileManager.default.fileExists(atPath: target))

    // A key other users can read is not used to sign.
    chmod(path, 0o644)
    #expect(throws: RegistrySigner.SignerError.self) { try RegistrySigner.readPrivateKey(at: path) }
}

@Test func packFilesAreCheckedAgainstTheIndexTheyAreListedIn() throws {
    let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
    func index(_ json: Data) throws -> RegistryIndex {
        let key = Curve25519.Signing.PrivateKey()
        return try RegistrySigner.signAndRead(indexJSON: json, privateKey: key.rawRepresentation).index
    }
    let file = dir.appendingPathComponent("n.json")
    // Not there: not checked. There and right: fine. There and different: named.
    #expect(RegistrySigner.checkPacks(try index(indexJSON()), directory: dir) == [])
    try packBytes.write(to: file)
    #expect(RegistrySigner.checkPacks(try index(indexJSON()), directory: dir) == [])
    let wrong = RegistrySigner.checkPacks(try index(indexJSON(sha: String(repeating: "0", count: 64))), directory: dir)
    #expect(wrong.count == 1 && wrong[0].hasPrefix("notes-extras: "))
}
