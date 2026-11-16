import Foundation

/// A draft app pack made from an app's top-level menu items, for `nohands-cli pack new`. One command per item, one
/// phrase per command. The pack validator decides what may stay: each candidate is parsed alone as a one-command
/// pack, and its reason is the validator's own, so no rule is restated here.
public enum PackDraft {
    /// A menu item that is not in the draft: `item` is its path (`File > Close All`), `reason` says why.
    public struct LeftOut: Equatable, Sendable {
        public let item: String
        public let reason: String
    }

    public enum Problem: Equatable, Sendable {
        /// The bundle ID or name is one the validator rejects.
        case badBundleID
        /// Every item was left out.
        case nothingToPut
        /// The finished draft failed the validator (it should not); the reason.
        case invalid(String)
    }

    public struct Result: Sendable {
        /// The draft, parsed back from `data`; nil with a `problem`.
        public let pack: AppPack?
        /// The pack file, as `PackFile.encode` writes it.
        public let data: Data?
        public let leftOut: [LeftOut]
        public let problem: Problem?
    }

    /// The most words and characters a phrase may have (the validator's limits); the validator still has the last word.
    private static let maxWords = 8, maxPhraseLength = 60

    public static func make(appName: String, bundleID: String, entries: [MenuEntry]) -> Result {
        let name = String(cleaned(appName).prefix(60))
        let probe = AppPack(id: "probe-pack", name: name.isEmpty ? String(bundleID.prefix(60)) : name, bundleIDs: [bundleID],
                            phrases: ["probe": [.pressKey(KeyChord(.f1))]])
        guard (try? PackFile.parse(PackFile.encode(probe))) != nil else {
            return Result(pack: nil, data: nil, leftOut: [], problem: .badBundleID)
        }
        let grammar = CommandGrammar(packs: .builtIns)
        var phrases: [String: [Action]] = [:]
        var owners: [String: String] = [:]
        var leftOut: [LeftOut] = []
        for entry in entries {
            let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let item = (entry.path + [title]).joined(separator: " > ")
            func skip(_ reason: String) { leftOut.append(LeftOut(item: item, reason: reason)) }
            guard entry.enabled else { skip("disabled"); continue }
            guard !entry.hasSubmenu else { skip("opens a submenu"); continue }
            guard !title.isEmpty else { skip("no title"); continue }
            guard !(entry.path + [title]).contains(where: { $0.contains(">") }) else { skip("title has >"); continue }
            let words = phrase(title)
            guard !words.isEmpty else { skip("no words to say"); continue }
            guard words.count <= maxPhraseLength, words.split(separator: " ").count <= maxWords else { skip("too long to say"); continue }
            if let earlier = owners[words] { skip("same phrase as \(earlier)"); continue }
            let bare = PhraseLead.strip(CommandGrammar.normalize(words)).tokens.joined(separator: " ")
            guard ![words, bare].contains(where: { !$0.isEmpty && grammar.parse($0, frontmost: bundleID) != nil }) else {
                skip("already a NoHands phrase"); continue
            }
            let menuItem = Action.menuItem(item)
            let action = entry.shortcut.map(Action.pressKey) ?? menuItem
            // The title is checked as a menu item too, so a shortcut cannot hide an irreversible item.
            guard IrreversibleGuard.held([action, menuItem], labels: [:], goal: "") == nil else { skip("irreversible"); continue }
            do {
                _ = try PackFile.parse(PackFile.encode(AppPack(id: probe.id, name: probe.name, bundleIDs: [bundleID],
                                                               phrases: [words: [action]])))
            } catch {
                skip("rejected: " + error.reason.replacingOccurrences(of: "command 1: ", with: "")); continue
            }
            guard phrases.count < PackFile.maxCommands else { skip("over the \(PackFile.maxCommands) command limit"); continue }
            phrases[words] = [action]
            owners[words] = item
        }
        guard !phrases.isEmpty else { return Result(pack: nil, data: nil, leftOut: leftOut, problem: .nothingToPut) }
        let draft = AppPack(id: id(for: bundleID), name: probe.name, bundleIDs: [bundleID], phrases: phrases)
        let data = PackFile.encode(draft)
        do {
            return Result(pack: try PackFile.parse(data), data: data, leftOut: leftOut, problem: nil)
        } catch {
            return Result(pack: nil, data: nil, leftOut: leftOut, problem: .invalid(error.reason))
        }
    }

    /// The bundle ID lowercased, anything but a letter or digit turned into `-`, runs collapsed, cut to 40, trailing `-`
    /// dropped: `com.apple.Safari` is `com-apple-safari`. A built-in pack's id gets `-custom`, a short one `app-` first.
    static func id(for bundleID: String) -> String {
        var id = ""
        for c in bundleID.lowercased() {
            let kept = c.isASCII && (c.isLetter || c.isNumber)
            if kept { id.append(c) } else if id.last != "-" { id.append("-") }
        }
        id = String(id.prefix(40))
        id = id.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if id.count < 2 { id = "app-" + id }
        return AppPacks.all.contains { $0.id == id } ? id + "-custom" : id
    }

    /// The title as a phrase: lowercased, `…` and `...` removed, anything but a letter, digit, apostrophe or space turned
    /// into a space, spaces collapsed. `Save As…` is `save as`.
    static func phrase(_ title: String) -> String {
        let text = title.lowercased().replacingOccurrences(of: "...", with: "").replacingOccurrences(of: "…", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "'")
        return String(text.map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " })
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func cleaned(_ text: String) -> String {
        let bad: Set<Unicode.GeneralCategory> = [.control, .format, .lineSeparator, .paragraphSeparator]
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.filter { !bad.contains($0.properties.generalCategory) })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
