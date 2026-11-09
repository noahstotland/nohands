import Foundation

/// How plan text is compared everywhere: lower-cased, accents folded, letters and digits only, spaces removed.
/// "outdoorboys" matches "Outdoor Boys - Home".
public enum PlanText {
    static func fold(_ s: String) -> String {
        String(s.lowercased().folding(options: .diacriticInsensitive, locale: nil).filter { $0.isLetter || $0.isNumber })
    }

    /// Whether `needle` appears in `haystack` once both are folded. An empty needle never matches.
    public static func matches(_ needle: String, in haystack: String) -> Bool {
        let n = fold(needle)
        return !n.isEmpty && fold(haystack).contains(n)
    }
}

/// Whether a goal is worth a planning request. A request costs a model round trip (and on the local model it
/// displaces the cached prompt prefix), so only goals that look multi-step get one; every other goal runs as before.
public enum PlanGate {
    private static let browsers: [[String]] = [
        ["safari"], ["chrome"], ["firefox"], ["arc"], ["brave"], ["opera"], ["vivaldi"], ["orion"], ["microsoft", "edge"],
    ]
    /// The plan cannot see the screen, so a goal about what is on it stays with the loop.
    private static let screenWords: Set<String> = ["this", "current", "here"]

    public static func mayPlan(goal: String) -> Bool {
        let words = CommandGrammar.normalize(goal)
        guard words.count >= 4, screenWords.isDisjoint(with: words) else { return false }
        // A plan has no browser field, so a goal that names a browser keeps the loop, which honours it.
        if browsers.contains(where: { contains(words, $0) }) { return false }
        return MediaGoal.matches(goal) || namesSite(goal: goal, words: words)
    }

    private static func namesSite(goal: String, words: [String]) -> Bool {
        if WebAddress.knownSites.keys.contains(where: { $0.count > 1 && contains(words, $0.split(separator: " ").map(String.init)) }) {
            return true
        }
        return goal.split(whereSeparator: { $0.isWhitespace }).contains { WebAddress.typedAddress(String($0)) != nil }
    }

    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }
}
