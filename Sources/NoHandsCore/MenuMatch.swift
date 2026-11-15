import Foundation

/// One item in an app's menu bar, as read by the Mac layer. The Apple menu is never included.
public struct MenuEntry: Equatable, Sendable {
    public let title: String
    /// The menus above the item, the menu bar item first: ["File"], or ["File", "Open Recent"] for a submenu item.
    public let path: [String]
    public let enabled: Bool
    /// An item that only opens a submenu: pressing it does nothing, so it is never a match.
    public let hasSubmenu: Bool

    public init(title: String, path: [String], enabled: Bool, hasSubmenu: Bool = false) {
        self.title = title
        self.path = path
        self.enabled = enabled
        self.hasSubmenu = hasSubmenu
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
        for tail in ["…", "..."] where t.hasSuffix(tail) { t = String(t.dropLast(tail.count)).trimmingCharacters(in: .whitespaces) }
        return t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Titles in the Apple menu: never pressed by name, whichever way the item is found.
    public static let appleMenuTitles: Set<String> = [
        "about this mac", "system settings", "system preferences", "app store", "recent items", "force quit",
        "sleep", "restart", "shut down", "lock screen", "log out",
    ]

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
            guard !entries[i].hasSubmenu else { return false }
            let path = entries[i].path.map { fold($0) }
            return path.count >= parts.count && Array(path.prefix(parts.count)) == parts
        }
        let folded = Dictionary(uniqueKeysWithValues: candidates.map { ($0, fold(entries[$0].title)) })
        let tiers: [([String]) -> Bool] = [
            { $0 == words },
            { $0.starts(with: words) },
            { title in words.allSatisfy(title.contains) },
        ]
        let spokenPlain = plain(spoken.split(separator: ">").last.map(String.init) ?? spoken)
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
