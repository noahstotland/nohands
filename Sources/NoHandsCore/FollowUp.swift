import Foundation

/// Follow-up requests ("no, the other one"): which words refer back to the last task, and when its memory still applies.
public enum FollowUp {
    /// Phrases that open a follow-up, matched as whole words at the start of the request.
    private static let openers: [[String]] = [
        ["no"], ["nope"], ["not", "that"], ["not", "this"], ["the", "other"], ["other", "one"], ["the", "next"],
        ["next", "one"], ["the", "previous"], ["instead"], ["also"], ["and", "then"], ["and", "also"],
        ["go", "back", "to"], ["actually"], ["wrong", "one"],
    ]

    /// Whether `goal` starts like a follow-up. Grammar commands never get here (the pipeline asks only about words
    /// the grammar did not take), so "go back" alone is still the browser command. An opener must be followed by at
    /// least one more word when it is a single word: a lone "no" or "actually" is not a request.
    public static func refers(_ goal: String) -> Bool {
        let words = CommandGrammar.normalize(goal.filter { !$0.isPunctuation })
        return openers.contains { (words.count > $0.count || $0.count > 1) && words.starts(with: $0) }
    }

    /// The goal words the done-only-when-playing check reads: the earlier goal joined to `goal`, unless `goal` asks to
    /// pause, stop or mute ("no, pause it" must not be held to the earlier "play ...").
    public static func playbackGoal(earlier: String?, goal: String) -> String {
        let stopWords: Set<String> = ["pause", "stop", "mute"]
        let words = goal.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard let earlier, !words.contains(where: stopWords.contains) else { return goal }
        return "\(earlier) \(goal)"
    }

    /// The goal a follow-up keeps for the next one: the earlier goal, then the new words whole. Over `limit`, the older
    /// part is cut (its start, the first goal, lasts longest), never the new words.
    public static func chained(earlier: String, goal: String, limit: Int) -> String {
        let hop = "; then: " + goal
        if hop.count >= limit { return String(goal.prefix(limit)) }
        return String(earlier.prefix(limit - hop.count)) + hop
    }

    /// The earlier task a request for `goal` follows up on, or nil for a normal request: a task was kept, the window
    /// (`windowMs`, 0 = off) has not passed since it ended, and the words refer back.
    public static func memory(_ kept: EarlierTask?, endedAt: ContinuousClock.Instant, now: ContinuousClock.Instant,
                              windowMs: Int, goal: String) -> EarlierTask? {
        guard let kept, windowMs > 0, endedAt.duration(to: now) < .milliseconds(windowMs), refers(goal) else { return nil }
        return kept
    }
}
