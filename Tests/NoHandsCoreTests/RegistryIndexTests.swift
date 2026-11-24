import Testing
import Foundation
import CryptoKit
@testable import NoHandsCore

private typealias Doc = [String: Any]
private let signerBytes = Curve25519.Signing.PrivateKey().rawRepresentation
private var signer: Curve25519.Signing.PrivateKey { try! Curve25519.Signing.PrivateKey(rawRepresentation: signerBytes) }
private let trusted = [PackRegistry.TrustedKey(publicKey: signer.publicKey.rawRepresentation)]
private func json(_ doc: Doc) -> Data { (try? JSONSerialization.data(withJSONObject: doc)) ?? Data() }

private func entry(_ edit: (inout Doc) -> Void = { _ in }) -> Doc {
    var e: Doc = ["id": "notes-extras", "name": "Notes extras", "author": "Jane", "version": "1.2.0", "description": "Pin notes.",
                  "bundleIDs": ["com.apple.Notes"], "url": "https://packs.example.org/n.json", "sha256": String(repeating: "a", count: 64)]
    edit(&e)
    return e
}

/// A signed envelope; `edit` changes the index document, `envelopeEdit` the envelope, `prefix` the signed bytes.
private func envelope(_ packs: [Doc] = [entry()], index edit: (inout Doc) -> Void = { _ in }, envelope envEdit: (inout Doc) -> Void = { _ in },
                      signing: (Data) -> Data = PackRegistry.signingInput) -> Data {
    var index: Doc = ["format": 1, "serial": 7, "packs": packs]
    edit(&index)
    let bytes = json(index)
    var env: Doc = ["format": 1, "keyID": trusted[0].keyID, "index": bytes.base64EncodedString(),
                    "signature": ((try? signer.signature(for: signing(bytes))) ?? Data()).base64EncodedString()]
    envEdit(&env)
    return json(env)
}

@Test func indexParseAcceptsGoodAndRejectsEachRule() throws {
    let good = try RegistryIndex.parse(envelope: envelope(), trusting: trusted)
    #expect(good.serial == 7 && good.packs.first?.id == "notes-extras" && good.packs.first?.url.host == "packs.example.org")
    let rejects: [(String, String, Data)] = [
        ("bad JSON", "invalid JSON", Data("{".utf8)),
        ("missing key", "missing key", envelope(envelope: { $0["signature"] = nil })),
        ("unknown key", "unknown key", envelope(envelope: { $0["extra"] = 1 })),
        ("bad base64", "bad base64", envelope(envelope: { $0["signature"] = "!!" })),
        ("unknown keyID", "unknown signing key", envelope(envelope: { $0["keyID"] = "0000000000000000" })),
        ("other bytes", "signature", envelope(signing: { $0 + Data("x".utf8) })),
        ("no prefix", "signature", envelope(signing: { $0 })),
        ("oversize", "too large", Data(repeating: 0x20, count: RegistryIndex.maxEnvelopeBytes + 1)),
        ("envelope format 2", "format", envelope(envelope: { $0["format"] = 2 })),
        ("index format 2", "format", envelope(index: { $0["format"] = 2 })),
        ("negative serial", "serial", envelope(index: { $0["serial"] = -1 })),
        ("version 1.x", "version", envelope([entry { $0["version"] = "1.x" }])),
        ("http url", "url", envelope([entry { $0["url"] = "http://packs.example.org/n.json" }])),
        ("ip host", "url", envelope([entry { $0["url"] = "https://10.0.0.1/n.json" }])),
        ("localhost", "url", envelope([entry { $0["url"] = "https://localhost/n.json" }])),
        ("userinfo", "url", envelope([entry { $0["url"] = "https://me:pw@packs.example.org/n.json" }])),
        ("duplicate id", "duplicate id", envelope([entry(), entry()])),
        ("bad sha256", "sha256", envelope([entry { $0["sha256"] = "ABC" }])),
        ("bad id", "id", envelope([entry { $0["id"] = "Bad Id" }])),
        ("built-in id", "id", envelope([entry { $0["id"] = "terminal" }])),
    ]
    for (name, reason, data) in rejects {
        do { _ = try RegistryIndex.parse(envelope: data, trusting: trusted); Issue.record("\(name) accepted") } catch {
            #expect(error.reason.contains(reason), "\(name): \(error.reason)")
        }
    }
}

@Test func verifyPackChecksHashParserAndEntryMatch() throws {
    let pack: Doc = ["format": 1, "id": "notes-extras", "name": "Notes extras", "version": "1.2.0", "author": "Jane", "bundleIDs": ["com.apple.Notes"],
                     "commands": [["phrases": ["new note"], "actions": [["kind": "press_key", "key": "n", "modifiers": ["command"]]]]]]
    func hash(_ d: Data) -> String { RegistryIndex.hex(SHA256.hash(data: d)) }
    func parsed(_ p: Doc, _ edit: (inout Doc) -> Void = { _ in }, hashOf: Data? = nil) throws -> (Data, RegistryEntry) {
        let data = json(p)
        let index = try RegistryIndex.parse(envelope: envelope([entry { $0["sha256"] = hash(hashOf ?? data); edit(&$0) }]), trusting: trusted)
        return (data, index.packs[0])
    }
    let (data, good) = try parsed(pack)
    #expect(try RegistryIndex.verifyPack(data, against: good).id == "notes-extras")
    var wrongVersion = pack; wrongVersion["version"] = "1.3.0"
    var badPack = pack; badPack["commands"] = []
    let rejects: [(String, Data, RegistryEntry, String)] = [
        ("hash", Data("other".utf8), good, "did not match"),
        ("parse failure", json(badPack), try parsed(badPack).1, "pack failed checks"),
        ("id", data, try parsed(pack) { $0["id"] = "other-pack" }.1, "does not match its registry entry"),
        ("version", json(wrongVersion), try parsed(wrongVersion).1, "does not match its registry entry"),
        ("bundleIDs", data, try parsed(pack) { $0["bundleIDs"] = ["com.apple.Mail"] }.1, "does not match its registry entry"),
    ]
    for (name, bytes, entry, reason) in rejects {
        do { _ = try RegistryIndex.verifyPack(bytes, against: entry); Issue.record("\(name) accepted") } catch { #expect(error.reason.contains(reason), "\(name): \(error.reason)") }
    }
}

@Test func versionsCompareNumerically() {
    func v(_ s: String) -> PackVersion { PackVersion(s)! }
    #expect(v("1.2") == v("1.2.0") && v("1.2.0") < v("1.10") && v("2") > v("1.99.99.99"))
    for bad in ["1.x", "1.2.3.4.5", "", "1..2", "1234567", "-1", "\u{661}"] { #expect(PackVersion(bad) == nil, "\(bad)") }
}

@Test func registrySettingAndKeys() {
    let table: [(String?, PackRegistry.Setting)] = [
        (nil, .none), ("", .off), (PackRegistry.defaultURLPlaceholder, .none), ("https://x.invalid/i.json", .none),
        ("http://x.org/", .invalid("Registry URL must be https")),
        ("https://localhost/", .invalid("Registry URL needs a public host and no user or password")),
        ("https://user@x.org/", .invalid("Registry URL needs a public host and no user or password")),
        ("https://packs.example.org/i.json", .url(URL(string: "https://packs.example.org/i.json")!)),
    ]
    for (input, want) in table { #expect(PackRegistry.setting(urlString: input) == want, "\(input ?? "nil")") }
    let raw = signer.publicKey.rawRepresentation
    let custom = URL(string: "https://packs.example.org/i.json")!, builtIn = URL(string: PackRegistry.defaultURLPlaceholder)!
    let other = [PackRegistry.TrustedKey(publicKey: Data(repeating: 1, count: 32))]
    #expect(PackRegistry.trustedKeys(url: builtIn, customKey: raw.base64EncodedString(), defaults: other) == other)
    #expect(PackRegistry.trustedKeys(url: custom, customKey: raw.base64EncodedString(), defaults: other) == trusted)
    #expect(PackRegistry.trustedKeys(url: custom, customKey: nil, defaults: other).isEmpty)
    #expect(PackRegistry.trustedKeys(url: custom, customKey: Data(repeating: 1, count: 31).base64EncodedString()).isEmpty)
    #expect(PackRegistry.trustedKeys(url: builtIn, customKey: nil) == PackRegistry.defaultKeys)
}
