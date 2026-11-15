import Foundation

/// One item in an app's menu bar, as read by the Mac layer. The Apple menu is never included.
public struct MenuEntry: Equatable, Sendable {
    public let title: String
    /// The menus above the item, the menu bar item first: ["File"], or ["File", "Open Recent"] for a submenu item.
    public let path: [String]
    public let enabled: Bool

    public init(title: String, path: [String], enabled: Bool) {
        self.title = title
        self.path = path
        self.enabled = enabled
    }
}

/// Picks the menu item a spoken phrase names. Never a guess: an exact title, else the closest by words, else nothing.
public enum MenuMatch {
    /// Lowercase, "…" and "..." removed, apostrophes dropped, other punctuation turned into a space, whitespace collapsed.
    static func fold(_ text: String) -> [String] {
        var kept = text.lowercased()
            .replacingOccurrences(of: "...", with: "")
            .replacingOccurrences(of: "…", with: "")
        kept.removeAll { "'’‘`".contains($0) }
        let spaced = kept.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(spaced).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// The index in `entries` of the item `spoken` names, or nil. `spoken` may be a path ("file > save as"): that
    /// limits the search to that menu and matches the last part.
    /// 1. Exact: the folded titles are equal.
    /// 2. Closest: titles whose words start with the spoken words, then titles holding every spoken word as a whole word.
    /// Within a tier the shortest title wins, then menu bar order. There is no edit-distance guess.
    public static func firstMatch(_ spoken: String, in entries: [MenuEntry]) -> Int? {
        var parts = spoken.split(separator: ">", omittingEmptySubsequences: false).map { fold(String($0)) }
        guard let words = parts.popLast(), !words.isEmpty else { return nil }
        let candidates = entries.indices.filter { i in
            let path = entries[i].path.map { fold($0) }
            return path.count >= parts.count && Array(path.prefix(parts.count)) == parts
        }
        let folded = Dictionary(uniqueKeysWithValues: candidates.map { ($0, fold(entries[$0].title)) })
        let tiers: [([String]) -> Bool] = [
            { $0 == words },
            { $0.starts(with: words) },
            { title in words.allSatisfy(title.contains) },
        ]
        for matches in tiers {
            let hits = candidates.filter { !folded[$0]!.isEmpty && matches(folded[$0]!) }
            // min(by:) keeps the first of equals, which is menu bar order.
            if let best = hits.min(by: { folded[$0]!.joined(separator: " ").count < folded[$1]!.joined(separator: " ").count }) {
                return best
            }
        }
        return nil
    }
}
