import Foundation
import NoHandsCore

/// Whether the configured pack registry can be used, and if not, what to tell the user. Reads config only: nothing is fetched.
public enum RegistryStatus: Equatable, Sendable {
    case ready(URL, [PackRegistry.TrustedKey])
    /// `menu` is the short menu line, `reason` the sentence Browse and the CLI show.
    case unavailable(menu: String, reason: String)

    public init(config: AppConfig) {
        switch config.packRegistry {
        case .none:
            self = .unavailable(menu: "Registry: none set", reason: "No pack registry yet, set packRegistryURL in config.json")
        case .off:
            self = .unavailable(menu: "Registry: off", reason: "The pack registry is off (packRegistryURL is empty)")
        case .invalid(let why):
            self = .unavailable(menu: why, reason: why)
        case .url(let url):
            let keys = config.packRegistryTrustedKeys
            self = keys.isEmpty
                ? .unavailable(menu: "Registry: no key", reason: "Registry has no key, set packRegistryKey in config.json")
                : .ready(url, keys)
        }
    }

    /// The menu line: the host when the registry is usable.
    public var menuLine: String {
        switch self {
        case .ready(let url, _): "Registry: " + PackSummary.printable(url.host ?? "set")
        case .unavailable(let menu, _): menu
        }
    }
}
