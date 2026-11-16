import Foundation

/// Why a pack file was rejected. The reason names the rule, never the file's content, so it is safe to log.
public struct PackError: Error, Equatable, Sendable {
    public let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// The installable pack format (version 1): parsed and checked here, so a pack file is data and nothing else.
/// Limits and rejections are in `docs/superpowers/specs/2026-11-15-nh-80-installable-packs-design.md`.
public enum PackFile {
    static let maxBytes = 64 * 1024, maxCommands = 200, maxPhrases = 500, maxActions = 8, maxBundleIDs = 16

    /// The pack id pattern `^[a-z0-9][a-z0-9-]{1,39}$`; also the check before a pack folder is touched.
    public static func isValidID(_ id: String) -> Bool {
        let scalars = Array(id.unicodeScalars)
        func lower(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) || ("0"..."9").contains(c) }
        return (2...40).contains(scalars.count) && lower(scalars[0]) && scalars.dropFirst().allSatisfy { lower($0) || $0 == "-" }
    }

    /// The pack in `data`, or the first rule it breaks. Built-in pack ids are taken.
    public static func parse(_ data: Data) throws(PackError) -> AppPack {
        try parse(data, reservedIDs: Set(AppPacks.all.map(\.id)))
    }

    static func parse(_ data: Data, reservedIDs: Set<String>) throws(PackError) -> AppPack {
        guard data.count <= maxBytes else { throw PackError("file too large (over 64 KiB)") }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PackError("invalid JSON: not an object")
        }
        try expectKeys(root, required: ["format", "id", "name", "version", "author", "bundleIDs", "commands"], in: "pack")
        guard let format = root["format"] as? NSNumber, CFGetTypeID(format) != CFBooleanGetTypeID(), format.doubleValue == 1 else {
            throw PackError("unsupported format (must be 1)")
        }
        let id = try text(root["id"], "id", max: 40)
        guard isValidID(id) else { throw PackError("bad id (lowercase letters, digits and -, 2 to 40 characters)") }
        guard !reservedIDs.contains(id) else { throw PackError("reserved id (a built-in pack has it)") }
        let name = try text(root["name"], "name", max: 60)
        let version = try text(root["version"], "version", max: 20)
        let author = try text(root["author"], "author", max: 60, allowEmpty: true)
        guard let ids = root["bundleIDs"] as? [Any], (1...maxBundleIDs).contains(ids.count) else {
            throw PackError("bundleIDs needs 1 to \(maxBundleIDs) entries")
        }
        var bundleIDs = Set<String>()
        for raw in ids {
            guard let bundle = raw as? String, !bundle.isEmpty, bundle.count <= 255,
                  bundle.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else {
                throw PackError("bad bundle ID (letters, digits, . and - only)")
            }
            bundleIDs.insert(bundle)
        }
        guard let commands = root["commands"] as? [Any], !commands.isEmpty else { throw PackError("no commands") }
        guard commands.count <= maxCommands else { throw PackError("too many commands (over \(maxCommands))") }
        var phrases: [String: [Action]] = [:]
        var count = 0
        for (index, raw) in commands.enumerated() {
            do { try parseCommand(raw, into: &phrases, count: &count) } catch {
                throw PackError("command \(index + 1): \(error.reason)")
            }
        }
        return AppPack(id: id, name: name, version: version, author: author, bundleIDs: bundleIDs, phrases: phrases)
    }

    private static func parseCommand(_ raw: Any, into phrases: inout [String: [Action]], count: inout Int) throws(PackError) {
        guard let command = raw as? [String: Any] else { throw PackError("not an object") }
        try expectKeys(command, required: ["phrases", "actions"], in: "command")
        guard let list = command["actions"] as? [Any], !list.isEmpty else { throw PackError("no actions") }
        guard list.count <= maxActions else { throw PackError("too many actions (over \(maxActions))") }
        var actions: [Action] = []
        for item in list { actions.append(try parseAction(item)) }
        guard let spoken = command["phrases"] as? [Any], !spoken.isEmpty else { throw PackError("no phrases") }
        for item in spoken {
            count += 1
            guard count <= maxPhrases else { throw PackError("too many phrases (over \(maxPhrases))") }
            let phrase = try text(item, "phrase", max: 60)
            let words = CommandGrammar.normalize(phrase)
            guard !words.isEmpty else { throw PackError("empty phrase") }
            guard words.count <= 8 else { throw PackError("phrase too long (over 8 words)") }
            let key = words.joined(separator: " ")
            guard phrases[key] == nil else { throw PackError("duplicate phrase") }
            let bare = PhraseLead.strip(words).tokens.joined(separator: " ")
            for candidate in [key, bare] where StopWords.isStop(candidate) || CommandGrammar.isReservedGlobal(candidate) {
                throw PackError("reserved phrase (stop, mode and release phrases belong to NoHands)")
            }
            if let why = ShortcutGuard.blocked(actions, goal: phrase) { throw PackError("blocked phrase: \(why)") }
            if IrreversibleGuard.held(actions, labels: [:], goal: phrase) != nil {
                throw PackError("held phrase (an irreversible menu item the phrase does not name)")
            }
            phrases[key] = actions
        }
    }

    private static func parseAction(_ raw: Any) throws(PackError) -> Action {
        guard let o = raw as? [String: Any], let kind = o["kind"] as? String else { throw PackError("action has no kind") }
        switch kind {
        case "press_key":
            try expectKeys(o, required: ["kind", "key"], optional: ["modifiers"], in: kind)
            guard let key = (o["key"] as? String).flatMap(Key.init(rawValue:)) else { throw PackError("bad key") }
            var modifiers = Set<Modifier>()
            if let raw = o["modifiers"] {
                guard let names = raw as? [Any] else { throw PackError("bad modifier list") }
                for name in names {
                    guard let modifier = (name as? String).flatMap(Modifier.init(rawValue:)) else { throw PackError("bad modifier") }
                    modifiers.insert(modifier)
                }
            }
            return .pressKey(KeyChord(key, modifiers))
        case "menu_item":
            try expectKeys(o, required: ["kind", "title"], in: kind)
            return .menuItem(try text(o["title"], "title", max: 100))
        case "open_app":
            try expectKeys(o, required: ["kind", "app"], in: kind)
            return .openApp(try text(o["app"], "app", max: 60))
        case "open_url":
            try expectKeys(o, required: ["kind", "url"], in: kind)
            let spoken = try text(o["url"], "url", max: 2048)
            guard !spoken.contains(where: \.isWhitespace), let parts = URLComponents(string: spoken), parts.scheme?.lowercased() == "https",
                  parts.host?.isEmpty == false, parts.user == nil, parts.password == nil, let url = URL(string: spoken) else {
                throw PackError("bad url (https with a host, no user or password)")
            }
            return .openURL(url, app: nil)
        default:
            throw PackError("unknown action kind")
        }
    }

    private static func expectKeys(_ o: [String: Any], required: Set<String>, optional: Set<String> = [],
                                   in place: String) throws(PackError) {
        guard required.isSubset(of: o.keys) else { throw PackError("missing key in \(place)") }
        guard Set(o.keys).isSubset(of: required.union(optional)) else { throw PackError("unknown key in \(place)") }
    }

    /// A string within `max` characters and free of control, format and line-break characters.
    private static func text(_ value: Any?, _ field: String, max: Int, allowEmpty: Bool = false) throws(PackError) -> String {
        guard let s = value as? String else { throw PackError("\(field) is not text") }
        guard allowEmpty || !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw PackError("\(field) is empty") }
        guard s.count <= max else { throw PackError("\(field) too long (over \(max))") }
        let bad: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator]
        guard !s.unicodeScalars.contains(where: { bad.contains($0.properties.generalCategory) }) else {
            throw PackError("\(field) has a control character")
        }
        return s
    }

    /// The pack as a file. Phrases with equal actions share a command. A command with an action the format cannot
    /// express (every case but a key chord, menu item, app or https URL) is left out; the built-ins have none.
    public static func encode(_ pack: AppPack) -> Data {
        var groups: [(phrases: [String], actions: [Action])] = []
        for phrase in pack.phrases.keys.sorted() {
            let actions = pack.phrases[phrase] ?? []
            if let i = groups.firstIndex(where: { $0.actions == actions }) { groups[i].phrases.append(phrase) } else { groups.append(([phrase], actions)) }
        }
        let commands: [[String: Any]] = groups.compactMap { group in
            let encoded = group.actions.compactMap(json)
            return encoded.count == group.actions.count ? ["phrases": group.phrases, "actions": encoded] : nil
        }
        let root: [String: Any] = ["format": 1, "id": pack.id, "name": pack.name, "version": pack.version, "author": pack.author,
                                   "bundleIDs": pack.bundleIDs.sorted(), "commands": commands]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
    }

    private static func json(_ action: Action) -> [String: Any]? {
        switch action {
        case .pressKey(let chord):
            var o: [String: Any] = ["kind": "press_key", "key": chord.key.rawValue]
            if !chord.modifiers.isEmpty { o["modifiers"] = chord.modifiers.map(\.rawValue).sorted() }
            return o
        case .menuItem(let title): return ["kind": "menu_item", "title": title]
        case .openApp(let app): return ["kind": "open_app", "app": app]
        case .openURL(let url, let app) where app == nil: return ["kind": "open_url", "url": url.absoluteString]
        default: return nil
        }
    }
}
