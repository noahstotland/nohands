import Foundation

/// Reading the text of a page: joining the runs the accessibility walk collects into one capped line, spotting
/// generic link titles, and cutting the short `near:` hint that tells two "Watch" links apart. Pure logic; the walk
/// that feeds it lives in `NoHandsMac`.
public enum PageText {
    /// The most characters of page text in one reading.
    public static let limit = 4000
    /// The most characters of a `near:` hint.
    public static let nearLimit = 40
    /// Marks a page reading; set by code, so page content can't pick the longer limit.
    public static let readingLabel = "page"

    static let separator = " | "
    static let cutMark = " …"

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The runs trimmed and whitespace-collapsed, empties and a run equal to the one before it dropped, joined with
    /// ` | `. Over `limit` it keeps whole runs and ends with ` …`; a first run that alone is too long is cut mid-run.
    public static func join(_ runs: [String]) -> String {
        var kept: [String] = []
        for run in runs {
            let r = collapse(run)
            if !r.isEmpty, r != kept.last { kept.append(r) }
        }
        let all = kept.joined(separator: separator)
        guard all.count > limit else { return all }
        var out = ""
        for r in kept {
            let next = out.isEmpty ? r : out + separator + r
            if next.count + cutMark.count > limit { break }
            out = next
        }
        if out.isEmpty { out = String(all.prefix(limit - cutMark.count)) }
        return out + cutMark
    }

    static let genericTitles: Set<String> = [
        "watch", "watch now", "watch live", "play", "open", "more", "read more", "learn more", "details", "view",
        "view more", "see more", "here", "click here", "link", "",
    ]

    /// Whether a link or button title says nothing about its target ("Watch", "Read more", or no title at all).
    public static func isGeneric(_ title: String) -> Bool {
        var t = collapse(title).lowercased()
        while let last = t.last, ".,!?:;…»›>".contains(last) { t.removeLast() }
        return genericTitles.contains(t.trimmingCharacters(in: .whitespaces))
    }

    /// The last `nearLimit` characters of `text`, cut on a word boundary when it can; nil when nothing is left.
    public static func near(_ text: String) -> String? {
        let t = collapse(text)
        guard t.count > nearLimit else { return t.isEmpty ? nil : t }
        var tail = String(t.suffix(nearLimit))
        let cutMidWord = !t[t.index(t.endIndex, offsetBy: -nearLimit - 1)].isWhitespace
        if cutMidWord, let space = tail.firstIndex(of: " ") { tail = String(tail[tail.index(after: space)...]) }
        return tail.isEmpty ? nil : tail
    }
}
