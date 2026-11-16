import Foundation

/// What the user is shown before saying yes to a pack: who made it, which apps it acts in, and the things it can
/// reach outside them.
public struct PackSummary: Equatable, Sendable {
    public let name: String
    public let version: String
    public let author: String
    /// Bundle IDs, sorted.
    public let apps: [String]
    public let phraseCount: Int
    /// Hosts of every `open_url` action, sorted, no repeats.
    public let urlHosts: [String]
    /// Names of every `open_app` action, sorted, no repeats.
    public let openedApps: [String]
    /// Global phrases the pack overrides inside its apps, sorted.
    public let overriddenPhrases: [String]

    public init(_ pack: AppPack) {
        let actions = pack.phrases.values.flatMap { $0 }
        name = pack.name
        version = pack.version
        author = pack.author
        apps = pack.bundleIDs.sorted()
        phraseCount = pack.phrases.count
        urlHosts = Set(actions.compactMap { action -> String? in
            if case .openURL(let url, _) = action { return url.host } else { return nil }
        }).sorted()
        openedApps = Set(actions.compactMap { action -> String? in
            if case .openApp(let app) = action { return app } else { return nil }
        }).sorted()
        // Anything the global grammar parses by itself, patterns included ("press return", "open safari").
        let global = CommandGrammar(packs: PackSet([]))
        overriddenPhrases = pack.phrases.keys.filter { global.parse($0, frontmost: nil) != nil }.sorted()
    }
}

/// The packs the grammar looks phrases up in: an ordered list merged per bundle ID. The first pack to claim a phrase
/// for an app keeps it; a later pack's claim is `shadowed`. The array-literal form keeps the order as written.
public struct PackSet: Sendable, ExpressibleByArrayLiteral {
    public struct Shadowed: Equatable, Sendable {
        public let packID: String
        public let phrase: String
        public let winner: String
    }

    public static let builtIns = PackSet(AppPacks.all)

    public let packs: [AppPack]
    public let shadowed: [Shadowed]
    private let byApp: [String: [String: [Action]]]

    public init(_ packs: [AppPack]) {
        var owners: [String: [String: String]] = [:]
        var merged: [String: [String: [Action]]] = [:]
        var lost: [Shadowed] = []
        for pack in packs {
            for app in pack.bundleIDs.sorted() {
                for (phrase, actions) in pack.phrases.sorted(by: { $0.key < $1.key }) {
                    if let winner = owners[app]?[phrase], winner != pack.id {
                        let entry = Shadowed(packID: pack.id, phrase: phrase, winner: winner)
                        if !lost.contains(entry) { lost.append(entry) }
                    } else {
                        owners[app, default: [:]][phrase] = pack.id
                        merged[app, default: [:]][phrase] = actions
                    }
                }
            }
        }
        self.packs = packs
        shadowed = lost
        byApp = merged
    }

    public init(arrayLiteral packs: AppPack...) { self.init(packs) }

    /// The built-in packs first, so they win every clash, then the installed ones in install order.
    public init(installed: [AppPack]) { self.init(AppPacks.all + installed) }

    /// The merged phrase table for an app, nil when no pack covers it.
    func phrases(for bundleID: String) -> [String: [Action]]? { byApp[bundleID] }
}

/// The one-line status under a pack in the menu bar and in `nohands-cli pack list`.
public enum PackMenu {
    /// "12 phrases, 1 shadowed", or "invalid: unknown action kind" when the pack failed validation.
    public static func status(phrases: Int, shadowed: Int, invalidReason: String? = nil) -> String {
        if let invalidReason { return "invalid: \(invalidReason)" }
        return "\(phrases) \(phrases == 1 ? "phrase" : "phrases")" + (shadowed > 0 ? ", \(shadowed) shadowed" : "")
    }
}
