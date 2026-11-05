import Foundation

/// The optional attention word (config key `attentionWord`): when set, command mode acts only on utterances that
/// start with it. The word is matched in the transcript, not acoustically. Pure: no audio, no I/O.
public struct AttentionGate: Sendable, Equatable {
    public enum Result: Equatable, Sendable {
        /// The word is present; the rest of the transcript, original casing, word removed.
        case addressed(String)
        /// The word and nothing else.
        case wordOnly
        /// The gate is on and the word is not at the start.
        case notAddressed
        /// The gate is off: use the transcript as it is.
        case off
    }

    /// Normalized tokens of the attention word; empty means off.
    public let words: [String]
    public var isOn: Bool { !words.isEmpty }

    public static let off = AttentionGate(words: [])

    /// Spoken before the word without changing the meaning ("um, computer, go back", "hey computer").
    private static let fillers: Set<String> = ["um", "uh", "er", "oh", "ok", "okay", "hey"]
    private static let maxWords = 3

    private init(words: [String]) { self.words = words }

    /// Normalizes `configured` with `CommandGrammar.normalize`. Off when it is empty, longer than three words, or a
    /// stop phrase (a stop word as the attention word would make every "stop" look like an empty addressed command).
    public init(configured: String) {
        let tokens = CommandGrammar.normalize(configured)
        if tokens.isEmpty || tokens.count > Self.maxWords || StopWords.isStop(tokens.joined(separator: " ")) {
            self.init(words: [])
        } else {
            self.init(words: tokens)
        }
    }

    public func check(_ transcript: String) -> Result {
        guard isOn else { return .off }
        // One entry per word of the transcript: its normalized token and where it ends in the original string.
        // Normalizing per whitespace-separated chunk is the same as normalizing the whole string.
        var tokens: [String] = []
        var ends: [String.Index] = []
        for chunk in transcript.split(whereSeparator: { $0.isWhitespace }) {
            guard let token = CommandGrammar.normalize(String(chunk)).first else { continue }
            tokens.append(token)
            ends.append(chunk.endIndex)
        }
        var skipped = 0
        while true {
            let end = skipped + words.count
            if end <= tokens.count, Array(tokens[skipped..<end]) == words {
                let rest = transcript[ends[end - 1]...]
                    .drop(while: { $0.isWhitespace || ",.!?:".contains($0) })
                return CommandGrammar.normalize(String(rest)).isEmpty ? .wordOnly : .addressed(String(rest))
            }
            guard skipped < tokens.count, Self.fillers.contains(tokens[skipped]) else { return .notAddressed }
            skipped += 1
        }
    }

    /// A stop phrase, bare or addressed ("stop", "computer, stop"). Never depends on the gate being on.
    public func isStop(_ transcript: String) -> Bool {
        if StopWords.isStop(transcript) { return true }
        if case .addressed(let rest) = check(transcript) { return StopWords.isStop(rest) }
        return false
    }
}
