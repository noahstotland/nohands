import Foundation

public enum DictationFormatter {
    private enum Kind {
        case attach(String)      // no space before, space after (. , ? ! : ;)
        case opener(String)      // space before, none after
        case closer(String)      // none before, space after
        case joiner(String)      // none before, none after (hyphen)
        case newline(String)     // none before, none after, capitalizes next
        case word(String)        // spaced like an ordinary word (dash)
    }

    private static let twoWord: [String: Kind] = [
        "question mark": .attach("?"),
        "exclamation point": .attach("!"),
        "exclamation mark": .attach("!"),
        "new line": .newline("\n"),
        "new paragraph": .newline("\n\n"),
        "open quote": .opener("\""),
        "close quote": .closer("\""),
        "open paren": .opener("("),
        "close paren": .closer(")"),
    ]

    private static let oneWord: [String: Kind] = [
        "period": .attach("."),
        "comma": .attach(","),
        "colon": .attach(":"),
        "semicolon": .attach(";"),
        "dash": .word("-"),
        "hyphen": .joiner("-"),
        "dot": .joiner("."),
    ]

    static let punctuation: Set<Character> = [".", ",", "!", "?", ":", ";"]

    /// Spoken punctuation → characters, spacing, sentence capitalization. Pure function of one utterance.
    /// `capitalizeStart: false` leaves the first word's case alone (used mid-sentence by DictationSession).
    public static func format(_ transcript: String, capitalizeStart: Bool = true) -> String {
        let tokens = transcript.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        func key(_ s: String) -> String { s.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,!?")) }

        var out = ""
        var noSpace = true          // suppress the space before the next token
        var capNext = capitalizeStart
        var i = 0

        func capitalized(_ w: String) -> String {
            guard let idx = w.firstIndex(where: { $0.isLetter }) else { return w }
            return String(w[..<idx]) + w[idx].uppercased() + String(w[w.index(after: idx)...])
        }

        while i < tokens.count {
            var kind: Kind?
            if i + 1 < tokens.count, let k = twoWord[key(tokens[i]) + " " + key(tokens[i + 1])] {
                kind = k; i += 2
            } else if let k = oneWord[key(tokens[i])] {
                kind = k; i += 1
            }
            switch kind {
            case .attach(let s):
                // The recognizer often already punctuated ("world, period."): replace its punctuation.
                while let c = out.last, Self.punctuation.contains(c) { out.removeLast() }
                out += s
                noSpace = false
                if s != ":" && s != ";" && s != "," { capNext = true }
            case .closer(let s):
                out += s
                noSpace = false
            case .joiner(let s):
                out += s
                noSpace = true
            case .newline(let s):
                out += s
                noSpace = true
                capNext = true
            case .opener(let s):
                if !noSpace { out += " " }
                out += s
                noSpace = true
                capNext = false
            case .word(let s):
                if !noSpace { out += " " }
                out += s
                noSpace = false
            case nil:
                var w = tokens[i]; i += 1
                if capNext { w = capitalized(w) }
                if w.contains(where: { $0.isLetter }) { capNext = false }
                if !noSpace { out += " " }
                out += w
                noSpace = false
                if let last = w.last, ".?!".contains(last) { capNext = true }
            }
        }
        return out
    }
}

public struct DictationSession: Sendable {
    private var last = ""

    public init() {}

    /// Formats `transcript`, capitalizing only at a sentence start, and prefixes a space when the
    /// previous insertion left the cursor after text and the new text begins a word or phrase.
    public mutating func next(_ transcript: String) -> String {
        let atSentenceStart: Bool = {
            guard let c = last.last else { return true }
            return c.isNewline || ".?!".contains(c)
        }()
        var formatted = DictationFormatter.format(transcript, capitalizeStart: atSentenceStart)
        // The previous insertion already ended in punctuation and this one starts with the same (or, after a
        // sentence end, any) punctuation, e.g. "Hello world." then "period" -> drop the duplicate leading run.
        if let prev = last.last, DictationFormatter.punctuation.contains(prev),
           let lead = formatted.first, DictationFormatter.punctuation.contains(lead),
           lead == prev || ".!?".contains(prev) {
            formatted = String(formatted.drop(while: { DictationFormatter.punctuation.contains($0) }))
        }
        guard let first = formatted.first else { return "" }
        var result = formatted
        if let prev = last.last, !prev.isWhitespace, prev != "(",
           !first.isWhitespace, !".,;:!?)".contains(first) {
            result = " " + formatted
        }
        last = result
        return result
    }
}
