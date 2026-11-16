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
    /// the grammar did not take), so "go back" alone is still the browser command.
    public static func refers(_ goal: String) -> Bool {
        let words = CommandGrammar.normalize(goal.filter { !$0.isPunctuation })
        return openers.contains { words.starts(with: $0) }
    }

    /// The earlier task a request for `goal` follows up on, or nil for a normal request: a task was kept, the window
    /// (`windowMs`, 0 = off) has not passed since it ended, and the words refer back.
    public static func memory(_ kept: EarlierTask?, endedAt: ContinuousClock.Instant, now: ContinuousClock.Instant,
                              windowMs: Int, goal: String) -> EarlierTask? {
        guard let kept, windowMs > 0, endedAt.duration(to: now) < .milliseconds(windowMs), refers(goal) else { return nil }
        return kept
    }
}
