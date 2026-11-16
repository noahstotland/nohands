import Foundation
import CryptoKit

/// Why a registry file or a downloaded pack was refused. Names the rule, never the content.
public struct RegistryError: Error, Equatable, Sendable {
    public let reason: String
    init(_ reason: String) { self.reason = reason }
}

public struct RegistryEntry: Equatable, Sendable {
    public let id, name, author, version, description: String
    public let bundleIDs: [String]
    public let url: URL
    /// 64 lowercase hex characters: SHA-256 of the pack file.
    public let sha256: String
}

/// A signed registry index (format 1). The envelope is checked, then its signature over the exact index bytes, and only
/// then is the index read; one bad entry rejects the whole index. Layout: `docs/superpowers/specs/2026-11-16-nh-85-pack-marketplace-design.md`.
public struct RegistryIndex: Sendable {
    public static let maxEnvelopeBytes = 1 << 20
    static let maxPacks = 1000
    public let serial: Int
    public let packs: [RegistryEntry]

    public static func parse(envelope: Data, trusting keys: [PackRegistry.TrustedKey]) throws(RegistryError) -> RegistryIndex {
        guard envelope.count <= maxEnvelopeBytes else { throw RegistryError("registry file too large (over 1 MiB)") }
        let root = try object(envelope, "registry file")
        try expect(root, ["format", "keyID", "index", "signature"], "registry file")
        guard isOne(root["format"]) else { throw RegistryError("unsupported registry format (must be 1)") }
        guard let keyID = root["keyID"] as? String, let key = keys.first(where: { $0.keyID == keyID }) else {
            throw RegistryError("unknown signing key")
        }
        guard let indexText = root["index"] as? String, let index = Data(base64Encoded: indexText),
              let signatureText = root["signature"] as? String, let signature = Data(base64Encoded: signatureText) else {
            throw RegistryError("bad base64 in registry file")
        }
        guard let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key.publicKey),
              publicKey.isValidSignature(signature, for: PackRegistry.signingInput(index)) else {
            throw RegistryError("signature check failed")
        }
        let body = try object(index, "index")
        try expect(body, ["format", "serial", "packs"], "index")
        guard isOne(body["format"]) else { throw RegistryError("unsupported index format (must be 1)") }
        guard let serial = (body["serial"] as? NSNumber).flatMap(whole), serial >= 0 else { throw RegistryError("bad serial") }
        guard let list = body["packs"] as? [Any], list.count <= maxPacks else { throw RegistryError("packs must be a list of at most \(maxPacks)") }
        var seen = Set<String>()
        var entries: [RegistryEntry] = []
        for (n, raw) in list.enumerated() {
            do throws(RegistryError) {
                let entry = try readEntry(raw)
                guard seen.insert(entry.id).inserted else { throw RegistryError("duplicate id") }
                entries.append(entry)
            } catch { throw RegistryError("pack \(n + 1): \(error.reason)") }
        }
        return RegistryIndex(serial: serial, packs: entries)
    }

    /// The pack in `bytes` if it is the file the index promised: its SHA-256 matches, it passes every NH-80 pack rule,
    /// and its `id`, `version` and `bundleIDs` equal the entry's.
    public static func verifyPack(_ bytes: Data, against entry: RegistryEntry) throws(RegistryError) -> AppPack {
        guard hex(SHA256.hash(data: bytes)) == entry.sha256 else { throw RegistryError("download did not match the registry") }
        let pack: AppPack
        do { pack = try PackFile.parse(bytes) } catch { throw RegistryError("pack failed checks: \(error.reason)") }
        guard pack.id == entry.id, pack.version == entry.version, pack.bundleIDs == Set(entry.bundleIDs) else {
            throw RegistryError("pack does not match its registry entry (id, version or apps differ)")
        }
        return pack
    }

    private static func readEntry(_ raw: Any) throws(RegistryError) -> RegistryEntry {
        guard let o = raw as? [String: Any] else { throw RegistryError("not an object") }
        try expect(o, ["id", "name", "author", "version", "description", "bundleIDs", "url", "sha256"], "pack")
        let id = try text(o["id"], "id", max: 40)
        guard PackFile.isValidID(id), !AppPacks.all.contains(where: { $0.id == id }) else { throw RegistryError("bad id") }
        let name = try text(o["name"], "name", max: 60)
        let author = try text(o["author"], "author", max: 60, allowEmpty: true)
        let description = try text(o["description"], "description", max: 300, allowEmpty: true)
        let version = try text(o["version"], "version", max: 20)
        guard PackVersion(version) != nil else { throw RegistryError("bad version (1 to 4 numbers separated by dots)") }
        guard let bundles = o["bundleIDs"] as? [String], (1...PackFile.maxBundleIDs).contains(bundles.count),
              bundles.allSatisfy(PackFile.isValidBundleID) else { throw RegistryError("bad bundleIDs") }
        guard let urlText = o["url"] as? String, PackFile.isPublicHTTPSURL(urlText), let url = URL(string: urlText) else {
            throw RegistryError("bad url (https with a public host, no user or password)")
        }
        guard let sha = o["sha256"] as? String, sha.count == 64, sha.allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw RegistryError("bad sha256")
        }
        return RegistryEntry(id: id, name: name, author: author, version: version, description: description,
                             bundleIDs: bundles, url: url, sha256: sha)
    }

    private static func object(_ data: Data, _ place: String) throws(RegistryError) -> [String: Any] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw RegistryError("invalid JSON in \(place)")
        }
        return root
    }

    private static func text(_ value: Any?, _ field: String, max: Int, allowEmpty: Bool = false) throws(RegistryError) -> String {
        do { return try PackFile.text(value, field, max: max, allowEmpty: allowEmpty) } catch { throw RegistryError(error.reason) }
    }

    private static func expect(_ o: [String: Any], _ required: Set<String>, _ place: String) throws(RegistryError) {
        do { try PackFile.expectKeys(o, required: required, in: place) } catch { throw RegistryError(error.reason) }
    }

    private static func whole(_ n: NSNumber) -> Int? {
        CFGetTypeID(n) == CFBooleanGetTypeID() ? nil : Int(exactly: n.doubleValue)
    }

    private static func isOne(_ value: Any?) -> Bool { (value as? NSNumber).flatMap(whole) == 1 }

    static func hex(_ digest: some Sequence<UInt8>) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}
