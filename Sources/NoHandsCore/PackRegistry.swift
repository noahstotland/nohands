import Foundation
import CryptoKit

/// Where packs can be found and which keys vouch for the index there. Pure checks on strings and bytes: nothing here
/// reaches the network (the fetch lives in NoHandsMac).
public enum PackRegistry {
    /// Stands for "no registry chosen yet". Any `.invalid` host (a reserved name that never resolves) means none set.
    public static let defaultURLPlaceholder = "https://registry-not-chosen.invalid/index.json"
    /// Keys that vouch for the default registry only. Empty until a registry exists.
    public static let defaultKeys: [TrustedKey] = []

    public struct TrustedKey: Equatable, Sendable {
        /// 16 lowercase hex characters; only picks a key, trust comes from `publicKey`.
        public let keyID: String
        /// The raw 32-byte Ed25519 public key.
        public let publicKey: Data
        public init(keyID: String, publicKey: Data) {
            self.keyID = keyID
            self.publicKey = publicKey
        }
        public init(publicKey: Data) { self.init(keyID: PackRegistry.keyID(of: publicKey), publicKey: publicKey) }
    }

    /// The first 8 bytes of the SHA-256 of the raw public key, as 16 lowercase hex characters.
    public static func keyID(of publicKey: Data) -> String {
        SHA256.hash(data: publicKey).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public enum Setting: Equatable, Sendable {
        case none, off, url(URL), invalid(String)
    }

    /// The registry the config names: nil is the default placeholder (none set), `""` is off, a bad URL says why.
    public static func setting(urlString: String?) -> Setting {
        guard let raw = urlString else { return .none }
        if raw.isEmpty { return .off }
        if raw == defaultURLPlaceholder || URLComponents(string: raw)?.host?.lowercased().hasSuffix(".invalid") == true { return .none }
        guard URLComponents(string: raw)?.scheme?.lowercased() == "https" else { return .invalid("Registry URL must be https") }
        guard PackFile.isPublicHTTPSURL(raw), let url = URL(string: raw) else {
            return .invalid("Registry URL needs a public host and no user or password")
        }
        return .url(url)
    }

    /// The keys that may vouch for `url`: the built-in keys for the default registry, otherwise only the user's key
    /// (base64 of the 32-byte public key), and none when it is missing or malformed.
    static func trustedKeys(url: URL, customKey: String?, defaults: [TrustedKey] = defaultKeys) -> [TrustedKey] {
        if url.absoluteString == defaultURLPlaceholder { return defaults }
        guard let customKey, let raw = Data(base64Encoded: customKey), raw.count == 32 else { return [] }
        return [TrustedKey(publicKey: raw)]
    }

    /// What a registry signs: a fixed prefix, then the index bytes, so a signature over anything else is not one.
    public static func signingInput(_ index: Data) -> Data {
        Data("nohands-pack-index-v1\n".utf8) + index
    }
}
