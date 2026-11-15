import Foundation

/// A span of a text field's value in UTF-16 offsets, the unit Accessibility ranges use.
public struct TextSpan: Equatable, Codable, Sendable {
    public var location: Int
    public var length: Int
    public init(location: Int, length: Int) { self.location = location; self.length = length }
    public var end: Int { location + length }
}

/// Pure range maths for the text-editing voice commands. Everything works on UTF-16 offsets into the value string,
/// so the offsets agree with Accessibility's on emoji and accents.
public enum TextRanges {
    // MARK: Character classes

    private static func isAlnum(_ c: UInt16) -> Bool {
        guard let s = Unicode.Scalar(c) else { return false }   // a surrogate half is never part of a word
        return s.properties.isAlphabetic || s.properties.numericType != nil
    }
    private static func isApostrophe(_ c: UInt16) -> Bool { c == 0x27 || c == 0x2019 }
    private static func isNewline(_ c: UInt16) -> Bool { c == 0x0A || c == 0x0D || c == 0x2028 || c == 0x2029 || c == 0x85 }
    private static func isSpace(_ c: UInt16) -> Bool {
        guard !isNewline(c), let s = Unicode.Scalar(c) else { return false }
        return s.properties.isWhitespace
    }
    private static func isWhitespace(_ c: UInt16) -> Bool { isNewline(c) || isSpace(c) }
    private static let closers: Set<UInt16> = Set("\"')]}\u{201D}\u{2019}\u{00BB}".utf16)
    private static let terminators: Set<UInt16> = Set(".?!".utf16)

    // MARK: Units

    /// A word is a run of letters and digits; an apostrophe between two of them stays inside ("don't").
    private static func wordRanges(_ u: [UInt16]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var i = 0
        while i < u.count {
            guard isAlnum(u[i]) else { i += 1; continue }
            var j = i + 1
            while j < u.count {
                if isAlnum(u[j]) { j += 1 }
                else if isApostrophe(u[j]), j + 1 < u.count, isAlnum(u[j + 1]) { j += 2 }
                else { break }
            }
            out.append(i..<j)
            i = j
        }
        return out
    }

    /// A sentence ends after `.`, `?` or `!` (and any closing quote or bracket) that is followed by whitespace or the
    /// end, or at a newline. Leading and trailing whitespace is not part of it.
    private static func sentenceRanges(_ u: [UInt16]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        let n = u.count
        var i = 0
        func emit(_ start: Int, _ end: Int) {
            var e = end
            while e > start, isWhitespace(u[e - 1]) { e -= 1 }
            if e > start { out.append(start..<e) }
        }
        while i < n {
            if isWhitespace(u[i]) { i += 1; continue }
            let start = i
            var j = i
            var end: Int?
            while j < n, end == nil {
                if isNewline(u[j]) { end = j }
                else if terminators.contains(u[j]) {
                    var k = j
                    while k < n, terminators.contains(u[k]) { k += 1 }
                    while k < n, closers.contains(u[k]) { k += 1 }
                    if k >= n || isWhitespace(u[k]) { end = k } else { j = k }
                } else { j += 1 }
            }
            let stop = end ?? n
            emit(start, stop)
            i = max(stop, start + 1)
        }
        return out
    }

    /// The text between newlines, empty ones left out.
    private static func paragraphRanges(_ u: [UInt16]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start = 0
        for i in 0...u.count where i == u.count || isNewline(u[i]) {
            if i > start { out.append(start..<i) }
            start = i + 1
        }
        return out
    }

    /// The range for `last` (the last one ending at or before the caret) or the one the caret is in or touching, else
    /// the last one before it.
    private static func pick(_ ranges: [Range<Int>], caret: Int, last: Bool) -> Range<Int>? {
        if !last, let hit = ranges.first(where: { $0.lowerBound <= caret && caret <= $0.upperBound }) { return hit }
        return ranges.last(where: { $0.upperBound <= caret })
    }

    private static func clamp(_ caret: Int, _ n: Int) -> Int { min(max(caret, 0), n) }

    /// The unit at the caret (or, with `last`, the last whole one that ends at or before it). `line` is the visual
    /// line the field reports for the caret; without one a line is the paragraph. nil when there is no such unit.
    public static func unit(_ unit: TextUnit, last: Bool, in text: String, caret: Int, line: TextSpan? = nil) -> TextSpan? {
        let u = Array(text.utf16)
        let caret = clamp(caret, u.count)
        let picked: Range<Int>?
        switch unit {
        case .word: picked = pick(wordRanges(u), caret: caret, last: last)
        case .sentence: picked = pick(sentenceRanges(u), caret: caret, last: last)
        case .paragraph: picked = pick(paragraphRanges(u), caret: caret, last: last)
        case .line:
            if !last, let line, line.location >= 0, line.end <= u.count {
                var end = line.end
                while end > line.location, isNewline(u[end - 1]) { end -= 1 }
                picked = end > line.location ? line.location..<end : nil
            } else {
                picked = pick(paragraphRanges(u), caret: caret, last: last)
            }
        }
        return picked.map { TextSpan(location: $0.lowerBound, length: $0.count) }
    }

    /// What deleting `range` removes. A word, sentence or phrase (`unit` nil) also takes one adjacent space, the one
    /// after it, else the one before, so no double space is left. A line or paragraph takes its newline.
    public static func deletion(of range: TextSpan, unit: TextUnit?, in text: String) -> TextSpan {
        let u = Array(text.utf16)
        guard range.location >= 0, range.end <= u.count else { return range }
        var (start, end) = (range.location, range.end)
        if unit == .line || unit == .paragraph {
            if end < u.count, isNewline(u[end]) {
                end += (u[end] == 0x0D && end + 1 < u.count && u[end + 1] == 0x0A) ? 2 : 1
            } else if start > 0, isNewline(u[start - 1]) {
                start -= (u[start - 1] == 0x0A && start > 1 && u[start - 2] == 0x0D) ? 2 : 1
            }
        } else if end < u.count, isSpace(u[end]) {
            end += 1
        } else if start > 0, isSpace(u[start - 1]) {
            start -= 1
        }
        return TextSpan(location: start, length: end - start)
    }

    // MARK: Phrases

    /// Where the speaker's words are in the text: case-insensitive, on word boundaries, any whitespace run matching a
    /// space, the phrase's trailing ASR punctuation dropped. The nearest match that ends at or before the caret wins;
    /// with none before, the nearest after. nil when the words are not there. No fuzzy matching.
    public static func find(_ phrase: String, in text: String, caret: Int) -> TextSpan? {
        var words = phrase.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        while let last = words.last, let c = last.last, ".,!?".contains(c) {
            words[words.count - 1].removeLast()
            if words[words.count - 1].isEmpty { words.removeLast() }
        }
        guard let first = words.first?.first, let lastChar = words.last?.last else { return nil }
        func piece(_ word: String) -> String {
            word.map { $0 == "'" || $0 == "\u{2019}" ? "['\u{2019}]" : NSRegularExpression.escapedPattern(for: String($0)) }.joined()
        }
        let alnum = #"[\p{L}\p{N}]"#
        var pattern = words.map(piece).joined(separator: #"\s+"#)
        if first.isLetter || first.isNumber { pattern = "(?<!\(alnum))(?<!\(alnum)['\u{2019}])" + pattern }
        if lastChar.isLetter || lastChar.isNumber { pattern += "(?!\(alnum))(?!['\u{2019}]\(alnum))" }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let length = (text as NSString).length
        let caret = clamp(caret, length)
        let hits = regex.matches(in: text, range: NSRange(location: 0, length: length)).map(\.range)
        let pick = hits.last(where: { $0.location + $0.length <= caret }) ?? hits.first
        return pick.map { TextSpan(location: $0.location, length: $0.length) }
    }

    /// `replacement` as it should be typed over `found`: a capital first letter is copied onto a lowercase start.
    public static func replacement(_ replacement: String, replacing found: String) -> String {
        guard let f = found.first, f.isUppercase, let r = replacement.first, r.isLowercase else { return replacement }
        return r.uppercased() + replacement.dropFirst()
    }

    // MARK: Case

    /// What a case command acts on: the selection, else the word that ends at the caret (or the last one before it).
    public static func caseTarget(in text: String, selection: TextSpan) -> TextSpan? {
        if selection.length > 0 { return selection }
        let u = Array(text.utf16)
        let caret = clamp(selection.location, u.count)
        let hit = wordRanges(u).last(where: { $0.upperBound <= caret })
        return hit.map { TextSpan(location: $0.lowerBound, length: $0.count) }
    }

    /// `capitalize` raises each word's first letter and leaves the rest; `upper` and `lower` change every letter.
    public static func changeCase(_ change: CaseChange, of text: String) -> String {
        switch change {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .capitalize:
            let u = Array(text.utf16)
            var out = ""
            var i = 0
            for word in wordRanges(u) {
                out += String(decoding: u[i..<word.lowerBound], as: UTF16.self)
                let w = String(decoding: u[word], as: UTF16.self)
                out += (w.first.map { $0.uppercased() } ?? "") + w.dropFirst()
                i = word.upperBound
            }
            return out + String(decoding: u[i...], as: UTF16.self)
        }
    }
}
