import Foundation

/// One item in an app's menu bar, as read by the Mac layer. The Apple menu is never included.
public struct MenuEntry: Equatable, Sendable {
    public let title: String
    /// The menus above the item, the menu bar item first: ["File"], or ["File", "Open Recent"] for a submenu item.
    public let path: [String]
    public let enabled: Bool
    /// An item that only opens a submenu: pressing it does nothing, so it is never a match.
    public let hasSubmenu: Bool
    /// The item's keyboard shortcut when the pack format can express it; only `pack new` reads it.
    public let shortcut: KeyChord?

    public init(title: String, path: [String], enabled: Bool, hasSubmenu: Bool = false, shortcut: KeyChord? = nil) {
        self.title = title
        self.path = path
        self.enabled = enabled
        self.hasSubmenu = hasSubmenu
        self.shortcut = shortcut
    }
}

/// Picks the menu item a spoken phrase names. Never a guess: an exact title, else the closest by words, else nothing.
public enum MenuMatch {
    /// Lowercase, "…" and "..." removed, apostrophes dropped, other punctuation turned into a space, whitespace collapsed.
    public static func fold(_ text: String) -> [String] {
        var kept = text.lowercased()
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "…", with: "")
        kept.removeAll { "'’‘`".contains($0) }
        let spaced = kept.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The title as the irreversible guard and the shortcut guard see it: lowercased, trailing "…" or "..." removed,
    /// whitespace collapsed, and nothing else changed. A model step must equal this, never the looser `fold`, so no
    /// character the fold deletes can turn a word the guards would catch ("Emp'ty Trash", "Se...nd") into a match.
    public static func plain(_ text: String) -> String {
        var t = text.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        for tail in ["…", "..."] where t.hasSuffix(tail) { t = String(t.dropLast(tail.count)).trimmingCharacters(in: .whitespaces) }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The part of a menu path that names the item to press: the last part of `path` split on ">" that is not empty
    /// once trimmed ("File > Open Recent > Empty" is "Empty"; "Send>" is "Send"), nil when no part has a character.
    /// The guards and both lookups in the executor use this one definition, so they cannot disagree on what is pressed.
    public static func leaf(of path: String) -> String? {
        path.split(separator: ">").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.last { !$0.isEmpty }
    }

    /// Non-Latin letters that look like a Latin one: Cyrillic, Greek and Armenian, lowercase and capitals.
    private static let confusables: [Character: Character] = {
        let pairs = [
            "аa", "еe", "оo", "рp", "сc", "уy", "хx", "ѕs", "іi", "јj", "һh", "ԁd", "ԛq", "ԝw",
            "АA", "ЕE", "ОO", "РP", "СC", "УY", "ХX", "ЅS", "ІI", "ЈJ", "ҺH",
            "οo", "αa", "νv", "ρp", "τt", "ιi", "κk",
            "ΑA", "ΒB", "ΕE", "ΖZ", "ΗH", "ΙI", "ΚK", "ΜM", "ΝN", "ΟO", "ΡP", "ΤT", "ΧX", "ΥY",
            "օo", "սu",
        ]
        return Dictionary(pairs.map { ($0.first!, $0.last!) }, uniquingKeysWith: { a, _ in a })
    }()

    /// Whether a title holds an ASCII word in disguise, checked word by word so another accented or CJK word beside it
    /// cannot hide it ("Sеnd Ägain" with a Cyrillic е). A word is a disguise when a non-ASCII letter in it reads as ASCII
    /// (NFKC, then look-alike Cyrillic, Greek and Armenian letters mapped to Latin) and the word either also holds a
    /// real ASCII letter or reads as ASCII all through. "Закрыть Safari", "Envoyer à nouveau" and "URLを開く" are not.
    public static func isLookalike(_ title: String) -> Bool {
        title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { word in
            var converted = 0, ascii = 0, other = 0
            for ch in word where ch.isLetter {
                if ch.isASCII { ascii += 1; continue }
                let skeleton = String(ch).precomposedStringWithCompatibilityMapping.map { confusables[$0] ?? $0 }
                if skeleton.allSatisfy({ !$0.isLetter || $0.isASCII }) { converted += 1 } else { other += 1 }
            }
            return converted > 0 && (ascii > 0 || other == 0)
        }
    }

    /// Titles in the Apple menu: never pressed by name, whichever way the item is found.
    public static let appleMenuTitles: Set<String> = [
        "about this mac", "system settings", "system preferences", "app store", "recent items", "force quit",
        "sleep", "restart", "shut down", "lock screen", "log out",
    ]

    /// Whether a title is an Apple menu item. "Log Out <name>…" carries the user's name, so it is matched by prefix.
    public static func isAppleMenuTitle(_ title: String) -> Bool {
        let t = plain(title)
        return appleMenuTitles.contains(t) || t.hasPrefix("log out ")
    }

    /// The index in `entries` of the item `spoken` names, or nil. `spoken` may be a path ("file > save as"): that
    /// limits the search to that menu and matches the last part.
    /// 1. Exact: the folded titles are equal.
    /// 2. Closest: titles whose words start with the spoken words, then titles holding every spoken word as a whole word.
    /// Within a tier the shortest title wins, then menu bar order. There is no edit-distance guess.
    /// `exactOnly` is for steps the model chose: the task guards check the name the model sent, so only the item
    /// with that very title may be pressed, never a longer title that happens to hold those words.
    public static func firstMatch(_ spoken: String, in entries: [MenuEntry], exactOnly: Bool = false) -> Int? {
        var parts = spoken.split(separator: ">", omittingEmptySubsequences: false).map { fold(String($0)) }
        guard let words = parts.popLast(), !words.isEmpty else { return nil }
        let candidates = entries.indices.filter { i in
            guard !entries[i].hasSubmenu, !isLookalike(entries[i].title) else { return false }
            let path = entries[i].path.map { fold($0) }
            return path.count >= parts.count && Array(path.prefix(parts.count)) == parts
        }
        let folded = Dictionary(uniqueKeysWithValues: candidates.map { ($0, fold(entries[$0].title)) })
        let tiers: [([String]) -> Bool] = [
            { $0 == words },
            { $0.starts(with: words) },
            { title in words.allSatisfy(title.contains) },
        ]
        let spokenPlain = plain(leaf(of: spoken) ?? spoken)
        for matches in exactOnly ? Array(tiers.prefix(1)) : tiers {
            let hits = candidates.filter {
                !folded[$0]!.isEmpty && matches(folded[$0]!) && (!exactOnly || plain(entries[$0].title) == spokenPlain)
            }
            // min(by:) keeps the first of equals, which is menu bar order.
            if let best = hits.min(by: { folded[$0]!.joined(separator: " ").count < folded[$1]!.joined(separator: " ").count }) {
                return best
            }
        }
        return nil
    }
}
