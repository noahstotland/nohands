import Foundation
import CryptoKit
import NoHandsCore

/// The publisher's side of a registry: making a signing key and signing an index file. Does no network I/O. The private
/// key is a file the publisher keeps (mode 600, raw 32 bytes as base64); it never goes in the repo, config or the app.
public enum RegistrySigner {
    public struct SignerError: Error, Equatable, Sendable {
        public let reason: String
        init(_ reason: String) { self.reason = reason }
    }

    /// Writes a new Ed25519 private key to `path` (mode 600) and returns its public key (base64, what `packRegistryKey`
    /// holds) and key id. Refuses an existing file or a symlink: the file is made with O_EXCL | O_NOFOLLOW, never replaced.
    public static func keygen(to path: String) throws -> (publicKeyBase64: String, keyID: String) {
        let key = Curve25519.Signing.PrivateKey()
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            throw SignerError(errno == EEXIST || errno == ELOOP ? "\(path) already exists (or is a link); choose a new path" : "can't create \(path)")
        }
        let line = Data((key.rawRepresentation.base64EncodedString() + "\n").utf8)
        let wrote = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) == $0.count }
        guard close(fd) == 0, wrote, fchmodat(AT_FDCWD, path, 0o600, 0) == 0 else {
            unlink(path)
            throw SignerError("can't write \(path)")
        }
        let publicKey = key.publicKey.rawRepresentation
        return (publicKey.base64EncodedString(), PackRegistry.keyID(of: publicKey))
    }

    /// The raw 32-byte key in the file at `path`. A symlink, a file other users can read or a malformed key is refused.
    public static func readPrivateKey(at path: String) throws -> Data {
        let file: (data: Data, mode: mode_t)?
        do { file = try ConfigFile.readRegularFile(path, limit: 1024) } catch { throw SignerError("can't read \(path): not a regular file") }
        guard let file else { throw SignerError("can't read \(path)") }
        guard file.mode & 0o077 == 0 else { throw SignerError("\(path) can be read by other users; run chmod 600 on it") }
        guard let raw = Data(base64Encoded: String(decoding: file.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)), raw.count == 32 else {
            throw SignerError("\(path) is not a key file made by registry keygen")
        }
        return raw
    }

    /// The signed envelope for `indexJSON`, after the index passes every registry rule under the key's own public key.
    public static func sign(indexJSON: Data, privateKey: Data) throws -> Data {
        try signAndRead(indexJSON: indexJSON, privateKey: privateKey).envelope
    }

    /// The envelope and the index read back from it, so the caller can check the packs the index lists.
    public static func signAndRead(indexJSON: Data, privateKey: Data) throws -> (envelope: Data, index: RegistryIndex) {
        guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: privateKey) else { throw SignerError("not a valid private key") }
        let publicKey = key.publicKey.rawRepresentation
        let keyID = PackRegistry.keyID(of: publicKey)
        guard let signature = try? key.signature(for: PackRegistry.signingInput(indexJSON)) else { throw SignerError("signing failed") }
        let document: [String: Any] = ["format": 1, "keyID": keyID, "index": indexJSON.base64EncodedString(), "signature": signature.base64EncodedString()]
        guard let envelope = try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]) else {
            throw SignerError("couldn't write the envelope")
        }
        do {
            return (envelope, try RegistryIndex.parse(envelope: envelope, trusting: [PackRegistry.TrustedKey(keyID: keyID, publicKey: publicKey)]))
        } catch { throw SignerError("index refused: \(error.reason)") }
    }

    /// Problems found by reading each listed pack from `directory` (named like the last part of its url) and running the
    /// download checks on it. A file that isn't there isn't checked; an empty list means every file that is there is right.
    public static func checkPacks(_ index: RegistryIndex, directory: URL) -> [String] {
        index.packs.compactMap { entry -> String? in
            let name = entry.url.lastPathComponent
            guard !name.isEmpty, !name.contains("/"), name != ".", name != "..",
                  let bytes = (try? ConfigFile.readRegularFile(directory.appendingPathComponent(name).path, limit: PackFile.maxBytes + 1))?.data else { return nil }
            do throws(RegistryError) { _ = try RegistryIndex.verifyPack(bytes, against: entry) } catch {
                return "\(PackSummary.printable(entry.id)): \(PackSummary.printable(error.reason))"
            }
            return nil
        }
    }
}
