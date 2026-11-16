import Foundation

/// The user's own words (config key `vocabulary`): each misheard spelling the recognizer produces is swapped for
/// the right one in every transcript. Pure text; no audio, no I/O. Decoding never fails: a bad entry is skipped
/// and counted in `skipped`.
public struct Vocabulary: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// Spellings the recognizer produces, as written in the config.
        public var hear: [String]
        public var say: String
    }

    public static let maxEntries = 200
    public static let maxHearWords = 5
    public static let maxSayCharacters = 100

    public private(set) var entries: [Entry]
    /// How many config entries were dropped (never the words themselves).
    public private(set) var skipped: Int

    public init() { entries = []; skipped = 0 }
    /// An empty list that counts a `vocabulary` value that was not a list as one skipped entry.
    init(skipped: Int) { entries = []; self.skipped = skipped }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([Lossy<Raw>].self)
        var kept: [Entry] = []
        for item in raw.prefix(Self.maxEntries) {
            if let raw = item.value, let entry = Self.clean(raw) { kept.append(entry) }
        }
        entries = kept
        skipped = raw.count - kept.count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(entries)
    }

    // MARK: Decoding and cleaning

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    private struct Raw: Decodable {
        var hear: [String]
        var say: String?
        private enum Keys: String, CodingKey { case hear, say }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            say = try? c.decodeIfPresent(String.self, forKey: .say)
            if let one = try? c.decodeIfPresent(String.self, forKey: .hear) {
                hear = [one]
            } else {
                hear = (try? c.decodeIfPresent([Lossy<String>].self, forKey: .hear))?.compactMap(\.value) ?? []
            }
        }
    }

    static func hasStopWord(_ text: String) -> Bool {
        let tokens = CommandGrammar.normalize(text)
        return tokens.contains(where: StopWords.isStop) || tokens.joined(separator: " ").contains("never mind")
    }

    private static func clean(_ raw: Raw) -> Entry? {
        guard let say = raw.say?.trimmingCharacters(in: .whitespacesAndNewlines),
              !say.isEmpty, say.count <= maxSayCharacters, !hasStopWord(say) else { return nil }
        let hear = raw.hear.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { spelling in
            let words = split(spelling).map { $0.core }
            return !words.isEmpty && words.count <= maxHearWords && !words.contains("") && !hasStopWord(spelling)
        }
        return hear.isEmpty ? nil : Entry(hear: hear, say: say)
    }

    // MARK: Matching

    /// A whitespace-separated word with its edge punctuation set aside.
    private struct Word { var lead: String; var core: String; var trail: String }

    private static func split(_ text: String) -> [Word] {
        text.split(whereSeparator: \.isWhitespace).map(word)
    }

    private static func word(_ chunk: Substring) -> Word {
        let isEdge: (Character) -> Bool = { !$0.isLetter && !$0.isNumber }
        let lead = chunk.prefix(while: isEdge)
        let rest = chunk.dropFirst(lead.count)
        let core = rest.reversed().drop(while: isEdge).reversed()
        return Word(lead: String(lead), core: String(core).lowercased(), trail: String(rest.dropFirst(core.count)))
    }

    /// What the pipeline hears: `apply`, except that a stop, a mode or release phrase ("wake up", "stop dictating",
    /// "command mode") is passed as heard, and so is any rewrite that would turn the words into a stop. The list can
    /// neither hide nor make a stop, nor take the user's way back out of a mode.
    public func rewrite(_ heard: String, attention: AttentionGate) -> String {
        func isReserved(_ text: String) -> Bool {
            if attention.isStop(text) { return true }
            var phrase = text
            if case .addressed(let rest) = attention.check(text) { phrase = rest }
            return CommandGrammar.isReservedGlobal(CommandGrammar.normalize(phrase).joined(separator: " "))
        }
        if isReserved(heard) { return heard }
        let out = apply(heard)
        return attention.isStop(out) ? heard : out
    }

    /// Returns `transcript` with each heard spelling replaced by its `say`. Whole words only, case-insensitive; the
    /// longest spelling wins, then the first entry; one left-to-right pass, so replaced text is never rescanned.
    public func apply(_ transcript: String) -> String {
        guard !entries.isEmpty else { return transcript }
        let spellings = entries.flatMap { e in e.hear.map { (words: Self.split($0).map(\.core), say: e.say) } }
        // Tokens keep the whitespace before them, so text between matches is copied as it was.
        var tokens: [(space: String, word: Word, original: Substring)] = []
        var index = transcript.startIndex
        while index < transcript.endIndex {
            let space = transcript[index...].prefix(while: \.isWhitespace)
            index = space.endIndex
            let chunk = transcript[index...].prefix(while: { !$0.isWhitespace })
            guard !chunk.isEmpty else { tokens.append((String(space), Word(lead: "", core: "", trail: ""), "")); break }
            tokens.append((String(space), Self.word(chunk), chunk))
            index = chunk.endIndex
        }
        var out = ""
        var i = 0
        while i < tokens.count {
            var best: (count: Int, say: String)?
            for s in spellings where s.words.count > (best?.count ?? 0) && i + s.words.count <= tokens.count {
                let n = s.words.count
                let window = tokens[i..<(i + n)]
                let joined = window.enumerated().allSatisfy { j, t in
                    t.word.core == s.words[j] && (j == n - 1 || t.word.trail.isEmpty) && (j == 0 || t.word.lead.isEmpty)
                }
                if joined { best = (n, s.say) }
            }
            out += tokens[i].space
            if let best {
                out += tokens[i].word.lead + best.say + tokens[i + best.count - 1].word.trail
                i += best.count
            } else {
                out += tokens[i].original
                i += 1
            }
        }
        return out
    }
}
