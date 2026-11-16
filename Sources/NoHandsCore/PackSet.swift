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
    /// One line per phrase, sorted: `"new note" -> command-N`, `"pin" -> menu item "Pin Note", open https://host/path`.
    /// Already escaped by `printable`.
    public let commandLines: [String]

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
        // Anything the global grammar parses by itself, patterns included ("press return", "open safari"), as spoken or
        // with its "open", "go to", "a" or "the" lead dropped, as a pack phrase is looked up.
        let global = CommandGrammar(packs: PackSet([]))
        overriddenPhrases = pack.phrases.keys.filter { phrase in
            let bare = PhraseLead.strip(CommandGrammar.normalize(phrase)).tokens.joined(separator: " ")
            return [phrase, bare].contains { !$0.isEmpty && global.parse($0, frontmost: nil) != nil }
        }.sorted()
        commandLines = pack.phrases.keys.sorted().map { phrase in
            Self.quoted(phrase) + " -> " + (pack.phrases[phrase] ?? []).map(Self.describe).joined(separator: ", ")
        }
    }

    /// An action in words: `command-shift-N`, `menu item "Archive Note"`, `open https://host/path`, `open app Foo`.
    static func describe(_ action: Action) -> String {
        switch action {
        case .pressKey(let chord):
            let order: [Modifier] = [.command, .option, .shift, .control, .function]
            let key = chord.key.rawValue.count == 1 ? chord.key.rawValue.uppercased() : chord.key.rawValue
            return (order.filter(chord.modifiers.contains).map(\.rawValue) + [key]).joined(separator: "-")
        case .menuItem(let title, _): return "menu item " + quoted(title)
        case .openURL(let url, _): return "open " + printable(url.absoluteString)
        case .openApp(let app): return "open app " + printable(app)
        default: return "(unsupported action)"
        }
    }

    /// `text` in quotes with backslash and quote escaped, and `printable` applied.
    public static func quoted(_ text: String) -> String {
        "\"" + printable(text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")) + "\""
    }

    /// `text` safe to print to a terminal: control, format, line and paragraph separator, private-use, unassigned and
    /// surrogate scalars, and spaces other than " ", become `\u{XXXX}`, so a pack cannot inject escape sequences or
    /// hide text with bidi marks.
    public static func printable(_ text: String) -> String {
        let bad: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator, .privateUse, .unassigned,
                                                 .surrogate, .spaceSeparator]
        return text.unicodeScalars.reduce(into: "") { out, scalar in
            if bad.contains(scalar.properties.generalCategory), scalar != " " {
                out += "\\u{" + String(scalar.value, radix: 16, uppercase: true) + "}"
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
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
