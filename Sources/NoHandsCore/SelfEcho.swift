import Foundation

/// A line NoHands is saying or just said. `end` is nil while it is still being spoken.
public struct SpokenLine: Equatable, Sendable {
    public let text: String
    public let start: ContinuousClock.Instant
    public var end: ContinuousClock.Instant?

    public init(text: String, start: ContinuousClock.Instant, end: ContinuousClock.Instant? = nil) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Backstop for NoHands hearing its own voice: a transcript that repeats the spoken line, heard while it played or
/// just after, is dropped before routing. It only ever drops; the caller checks a stop phrase first.
public enum SelfEcho {
    /// An utterance that ended in `[start, end + tail]` (no upper bound while the line is still playing) and whose
    /// normalized words are at least 70% words of the line (all of them when there are fewer than three).
    public static func isEcho(
        transcript: String,
        utteranceEnd: ContinuousClock.Instant,
        spoken: SpokenLine?,
        tail: Duration = .seconds(1)
    ) -> Bool {
        guard let spoken, utteranceEnd >= spoken.start else { return false }
        if let end = spoken.end, utteranceEnd > end + tail { return false }
        let words = CommandGrammar.normalize(transcript)
        guard !words.isEmpty else { return false }
        let line = Set(CommandGrammar.normalize(spoken.text))
        let matching = words.filter(line.contains).count
        return words.count < 3 ? matching == words.count : Double(matching) >= 0.7 * Double(words.count)
    }
}
