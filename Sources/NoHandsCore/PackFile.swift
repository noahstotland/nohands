import Foundation

/// Why a pack file was rejected. The reason names the rule, never the file's content, so it is safe to log.
public struct PackError: Error, Equatable, Sendable {
    public let reason: String
    init(_ reason: String) { self.reason = reason }
}

/// The installable pack format (version 1): parsed and checked here, so a pack file is data and nothing else.
/// Limits and rejections are in `docs/superpowers/specs/2026-11-15-nh-80-installable-packs-design.md`.
public enum PackFile {
    /// The most bytes a pack file may hold.
    public static let maxBytes = 64 * 1024
    static let maxCommands = 200, maxPhrases = 500, maxActions = 8, maxBundleIDs = 16

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
            guard let bundle = raw as? String, isValidBundleID(bundle) else {
                throw PackError("bad bundle ID (letters, digits, . and - only)")
            }
            bundleIDs.insert(bundle)
        }
        guard let commands = root["commands"] as? [Any], !commands.isEmpty else { throw PackError("no commands") }
        guard commands.count <= maxCommands else { throw PackError("too many commands (over \(maxCommands))") }
        var phrases: [String: [Action]] = [:]
        var parsed: [ParsedCommand] = []
        var count = 0
        for (index, raw) in commands.enumerated() {
            do { parsed.append(try parseCommand(raw, into: &phrases, count: &count)) } catch {
                throw PackError("command \(index + 1): \(error.reason)")
            }
        }
        // A command asks first when its phrase or actions say so (`forcesConfirm`), or it shares actions with one that
        // does, or the author set `"confirm": true`. Only an explicit false on a forced command is an error.
        let forcedActions: [[Action]] = parsed.filter { cmd in
            cmd.keys.contains { forcesConfirm(phrase: $0, actions: cmd.actions, bundleIDs: bundleIDs) }
        }.map(\.actions)
        var confirms = Set<String>()
        for (index, cmd) in parsed.enumerated() {
            let forced = forcedActions.contains { holdsRun(cmd.actions, $0) }
            if forced, cmd.confirm == false {
                throw PackError("command \(index + 1): confirm false on an irreversible command (it names send, delete or another guarded verb, or holds the actions of one that does)")
            }
            if forced || cmd.confirm == true { confirms.formUnion(cmd.keys) }
        }
        return AppPack(id: id, name: name, version: version, author: author, bundleIDs: bundleIDs, phrases: phrases, confirms: confirms)
    }

    private struct ParsedCommand {
        let keys: [String]
        let actions: [Action]
        let confirm: Bool?
    }

    /// Whether `actions` hold `marked` as a run of steps, ignoring the function modifier on key chords.
    private static func holdsRun(_ actions: [Action], _ marked: [Action]) -> Bool {
        func plain(_ list: [Action]) -> [Action] {
            list.map { action in
                guard case .pressKey(let chord) = action else { return action }
                return .pressKey(KeyChord(chord.key, chord.modifiers.subtracting([.function])))
            }
        }
        let have = plain(actions), run = plain(marked)
        guard !run.isEmpty, have.count >= run.count else { return false }
        return (0...(have.count - run.count)).contains { Array(have[$0..<($0 + run.count)]) == run }
    }

    /// Whether a phrase must ask for a spoken yes: its words name a guarded verb (or "trash"; "undo" frees nothing,
    /// since a chord or URL cannot be checked for what it undoes), or its actions contain a marked built-in command's
    /// actions (in a row, ignoring the function modifier) for an app both packs cover.
    static func forcesConfirm(phrase: String, actions: [Action], bundleIDs: Set<String>) -> Bool {
        if IrreversibleGuard.namesVerb(CommandGrammar.normalize(phrase)) { return true }
        return AppPacks.all.contains { pack in
            !pack.bundleIDs.isDisjoint(with: bundleIDs) && pack.confirms.contains { pack.phrases[$0].map { holdsRun(actions, $0) } ?? false }
        }
    }

    private static func parseCommand(_ raw: Any, into phrases: inout [String: [Action]], count: inout Int) throws(PackError) -> ParsedCommand {
        guard let command = raw as? [String: Any] else { throw PackError("not an object") }
        try expectKeys(command, required: ["phrases", "actions"], optional: ["confirm"], in: "command")
        var explicit: Bool?
        if let value = command["confirm"] {
            guard let flag = value as? NSNumber, CFGetTypeID(flag) == CFBooleanGetTypeID() else { throw PackError("bad confirm (true or false)") }
            explicit = flag.boolValue
        }
        guard let list = command["actions"] as? [Any], !list.isEmpty else { throw PackError("no actions") }
        guard list.count <= maxActions else { throw PackError("too many actions (over \(maxActions))") }
        var actions: [Action] = []
        for item in list { actions.append(try parseAction(item)) }
        try checkSequence(actions)
        guard let spoken = command["phrases"] as? [Any], !spoken.isEmpty else { throw PackError("no phrases") }
        var keys: [String] = []
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
            if blockedChord(actions, words: Set(words)) { throw PackError("blocked chord (app switching, launcher, force quit or empty Trash needs a phrase that says so)") }
            if IrreversibleGuard.held(actions, labels: [:], goal: phrase) != nil {
                throw PackError("held phrase (an irreversible menu item the phrase does not name)")
            }
            // Menu titles match by words at run time, so a short title can press a longer irreversible one.
            for case .menuItem(let title, _) in actions where IrreversibleGuard.namesLoosely(title: title, goal: phrase) != nil {
                throw PackError("held phrase (a menu_item title matches an irreversible item loosely; name the full title)")
            }
            phrases[key] = actions
            keys.append(key)
        }
        return ParsedCommand(keys: keys, actions: actions, confirm: explicit)
    }

    /// A key press with no command or option: it types a character, presses the focused button or sends a control
    /// character (control-letter chords count, so they cannot add up to typed text either).
    private static func isPlain(_ chord: KeyChord) -> Bool {
        chord.modifiers.isDisjoint(with: [.command, .option])
    }

    /// A press that activates the focused button: return and space with any modifiers (option-return and
    /// shift-option-return too), and control-m and control-j (a carriage return or line feed to a text field or a dialog).
    private static func isReturnLike(_ chord: KeyChord) -> Bool {
        switch chord.key {
        case .return, .space: return true
        case .m, .j: return chord.modifiers.contains(.control)
        default: return false
        }
    }

    /// Rules on a command's actions as a whole, so single presses cannot add up to typed text or to a press on a button
    /// the pack never named.
    private static func checkSequence(_ actions: [Action]) throws(PackError) {
        var plain = 0
        var opensDialog = false   // a menu item or a command chord: it may have opened a dialog with a default button
        for (index, action) in actions.enumerated() {
            switch action {
            case .pressKey(let chord):
                if isPlain(chord) {
                    plain += 1
                    if plain > 2 { throw PackError("too many key presses (over 2 without command or option: that would type text)") }
                }
                if opensDialog, isReturnLike(chord) {
                    throw PackError("return-like key (return, space, control-m, control-j) after a menu_item or command chord (it could press the button that opens)")
                }
                if chord.modifiers.contains(.command) { opensDialog = true }
            case .menuItem: opensDialog = true
            case .openApp, .openURL:
                if index != actions.count - 1 { throw PackError("open_app and open_url must be the last action (focus leaves the app)") }
            default: break
            }
        }
    }

    /// Chords that switch apps, open the launcher or force quit (command with space or tab, command-option-escape) are
    /// always blocked, and so is command-option-delete (Delete Immediately) without shift. The chords that empty the
    /// Trash (command with shift and delete or forward delete, with any other modifiers) are held unless the phrase
    /// says "empty" and "trash"; that exemption covers only them.
    private static func blockedChord(_ actions: [Action], words: Set<String>) -> Bool {
        let saysEmptyTrash = words.contains("empty") && words.contains("trash")
        return actions.contains { action in
            guard case .pressKey(let chord) = action, chord.modifiers.contains(.command) else { return false }
            switch chord.key {
            case .space, .tab: return true
            case .escape: return chord.modifiers.contains(.option)
            case .delete, .forwardDelete:
                if chord.modifiers.contains(.shift) { return !saysEmptyTrash }
                return chord.modifiers.contains(.option)
            default: return false
            }
        }
    }

    /// Whether an `open_url` host is not a plain public DNS name: anything outside ASCII letters, digits, `.` and `-`
    /// (a unicode host arrives as punycode, so it passes), an empty label (leading, trailing or double dots), an IP
    /// address or number, `localhost`, a name with no dot, or a local-network suffix. A public name can still resolve
    /// to a private address; this check does not look names up.
    private static func isLocalHost(_ host: String) -> Bool {
        let h = host.lowercased()
        guard !h.isEmpty, h.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }) else { return true }
        let labels = h.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ !$0.isEmpty }) else { return true }
        let dotted = "." + h
        guard ![".local", ".localhost", ".lan", ".internal", ".home.arpa"].contains(where: dotted.hasSuffix) else { return true }
        // A last label that is all digits or hex ("127.0.0.1", "0x7f.1") is an address; no real top level domain is.
        let last = String(labels[labels.count - 1])
        return last.allSatisfy(\.isNumber) || last.hasPrefix("0x")
    }

    enum HTTPSCheck { case ok(URL), badShape, badHost }

    /// The `open_url` rule: `https` with a host, no user or password, and a public host name.
    static func checkHTTPS(_ spoken: String) -> HTTPSCheck {
        guard !spoken.contains(where: \.isWhitespace), let parts = URLComponents(string: spoken), parts.scheme?.lowercased() == "https",
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil, let url = URL(string: spoken) else { return .badShape }
        // The raw host must not hide characters behind percent escapes. The host is checked as `URL.host` gives it
        // (punycode for a unicode name), and again as URLComponents does when that is plain ASCII.
        let rawHost = spoken.dropFirst("https://".count).prefix { !"/?#".contains($0) }
        let seen = [url.host ?? ""] + [parts.host ?? ""].filter { $0.allSatisfy(\.isASCII) }
        guard !rawHost.contains("%"), !seen.contains(where: isLocalHost) else { return .badHost }
        return .ok(url)
    }

    /// Whether `spoken` is an `https` URL with a public host, no user or password, up to 2048 characters (the pack
    /// `open_url` rule, shared with the registry's pack URLs).
    public static func isPublicHTTPSURL(_ spoken: String) -> Bool {
        guard spoken.count <= 2048, case .ok = checkHTTPS(spoken) else { return false }
        return true
    }

    static func isValidBundleID(_ bundle: String) -> Bool {
        !bundle.isEmpty && bundle.count <= 255 && bundle.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
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
            let title = try text(o["title"], "title", max: 100)
            // The executor presses the last part that has a name, so an empty part ("Send>", "File > > Save", ">Save")
            // would hide the real target from the checks.
            guard !title.split(separator: ">", omittingEmptySubsequences: false)
                .contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw PackError("bad menu_item title (empty part around >)")
            }
            guard !title.split(separator: ">").contains(where: { MenuMatch.isLookalike(String($0)) }) else {
                throw PackError("bad menu_item title (lookalike letters)")
            }
            return .menuItem(title, exact: true)
        case "open_app":
            try expectKeys(o, required: ["kind", "app"], in: kind)
            return .openApp(try text(o["app"], "app", max: 60))
        case "open_url":
            try expectKeys(o, required: ["kind", "url"], in: kind)
            let spoken = try text(o["url"], "url", max: 2048)
            switch checkHTTPS(spoken) {
            case .ok(let url): return .openURL(url, app: nil)
            case .badShape: throw PackError("bad url (https with a host, no user or password)")
            case .badHost:
                throw PackError("bad url (host must be a public name: ASCII letters, digits, . and - only; no IP address, localhost, .local, .lan, .internal, .home.arpa, empty label or name without a dot)")
            }
        default:
            throw PackError("unknown action kind")
        }
    }

    static func expectKeys(_ o: [String: Any], required: Set<String>, optional: Set<String> = [],
                                   in place: String) throws(PackError) {
        guard required.isSubset(of: o.keys) else { throw PackError("missing key in \(place)") }
        guard Set(o.keys).isSubset(of: required.union(optional)) else { throw PackError("unknown key in \(place)") }
    }

    /// A string within `max` characters and free of control, format and line-break characters.
    static func text(_ value: Any?, _ field: String, max: Int, allowEmpty: Bool = false) throws(PackError) -> String {
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
        var groups: [(phrases: [String], actions: [Action], asks: Bool)] = []
        for phrase in pack.phrases.keys.sorted() {
            let actions = pack.phrases[phrase] ?? []
            let asks = pack.confirms.contains(phrase)
            if let i = groups.firstIndex(where: { $0.actions == actions && $0.asks == asks }) {
                groups[i].phrases.append(phrase)
            } else {
                groups.append(([phrase], actions, asks))
            }
        }
        let commands: [[String: Any]] = groups.compactMap { group in
            let encoded = group.actions.compactMap(json)
            guard encoded.count == group.actions.count else { return nil }
            var command: [String: Any] = ["phrases": group.phrases, "actions": encoded]
            if group.asks { command["confirm"] = true }
            return command
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
        case .menuItem(let title, _): return ["kind": "menu_item", "title": title]
        case .openApp(let app): return ["kind": "open_app", "app": app]
        case .openURL(let url, let app) where app == nil: return ["kind": "open_url", "url": url.absoluteString]
        default: return nil
        }
    }
}
