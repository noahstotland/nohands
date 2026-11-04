import Foundation

/// Decides how long to hold a finished transcript before acting on it, so a speaker who pauses mid-command
/// ("click the … back button") gets both halves treated as one request instead of two broken ones.
public struct UtteranceMerger: Sendable {
    public var windowMs: Int
    public var unfinishedWindowMs: Int

    public init(windowMs: Int = 500, unfinishedWindowMs: Int = 1500) {
        self.windowMs = windowMs
        self.unfinishedWindowMs = unfinishedWindowMs
    }

    /// Words that practically never end a command: the speaker is still going.
    static let danglingWords: Set<String> = [
        "the", "a", "an", "to", "and", "or", "of", "in", "on", "at", "into", "onto", "for", "with", "then",
        "click", "press", "open", "type", "write", "select", "go", "move", "scroll", "zoom", "hit", "tap",
        "switch", "show", "hide", "find", "search", "um", "uh", "er", "like", "no", "wait", "actually",
    ]

    /// True when the transcript ends in a word that leaves the command hanging.
    public static func isUnfinished(_ transcript: String) -> Bool {
        guard let last = transcript.split(whereSeparator: { $0.isWhitespace }).last else { return false }
        let word = last.lowercased().trimmingCharacters(in: .punctuationCharacters)
        return danglingWords.contains(word)
    }

    /// `isComplete` says the transcript already parses as a full grammar command and can run at once.
    public func hold(for transcript: String, isComplete: Bool) -> Duration {
        if Self.isUnfinished(transcript) { return .milliseconds(unfinishedWindowMs) }
        if isComplete { return .zero }
        return .milliseconds(windowMs)
    }

    public static func merge(_ first: String, _ second: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}
