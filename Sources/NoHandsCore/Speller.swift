import Foundation

public enum SpellError: Error, Equatable, Sendable {
    case empty
    case unknown(String)
    case capitalWithoutLetter
}

/// Turns spoken letter names, NATO words, digits and a few separators into one typed string.
/// Tokens come from `CommandGrammar.normalize`. All or nothing: the first bad token fails the whole phrase.
public enum Speller {
    private static let letterWords: [String: Character] = {
        var table: [String: Character] = [:]
        for scalar in "abcdefghijklmnopqrstuvwxyz".unicodeScalars { table[String(scalar)] = Character(scalar) }
        let names: [Character: [String]] = [
            "a": ["alpha", "alfa"], "b": ["bee", "bravo"], "c": ["see", "sea", "charlie"], "d": ["dee", "delta"],
            "e": ["echo"], "f": ["foxtrot"], "g": ["gee", "golf"], "h": ["hotel"], "i": ["eye", "india"],
            "j": ["jay", "juliet", "juliett"], "k": ["kay", "kilo"], "l": ["el", "lima"], "m": ["em", "mike"],
            "n": ["en", "november"], "o": ["oh", "oscar"], "p": ["pee", "papa"], "q": ["queue", "cue", "quebec"],
            "r": ["are", "romeo"], "s": ["ess", "sierra"], "t": ["tee", "tea", "tango"], "u": ["you", "uniform"],
            "v": ["vee", "victor"], "w": ["whiskey", "whisky"], "x": ["ex", "xray", "x-ray"],
            "y": ["why", "yankee"], "z": ["zee", "zed", "zulu"],
        ]
        for (letter, words) in names { for w in words { table[w] = letter } }
        return table
    }()

    private static let digitWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    private static let separators: [String: String] = [
        "space": " ", "dash": "-", "dot": ".", "underscore": "_",
    ]

    public static func spell(_ tokens: [String]) -> Result<String, SpellError> {
        guard !tokens.isEmpty else { return .failure(.empty) }
        var out = ""
        var i = 0
        var capital = false
        while i < tokens.count {
            let t = tokens[i]
            let next = i + 1 < tokens.count ? tokens[i + 1] : nil
            i += 1
            if t == "capital" {
                guard !capital else { return .failure(.capitalWithoutLetter) }
                capital = true
                continue
            }
            var letter = letterWords[t]
            if t == "x", next == "ray" { letter = "x"; i += 1 }
            if t == "double", next == "you" { letter = "w"; i += 1 }
            if let letter {
                out += capital ? String(letter).uppercased() : String(letter)
                capital = false
                continue
            }
            guard !capital else { return .failure(.capitalWithoutLetter) }
            if let d = digitWords[t] {
                out += d
            } else if t.allSatisfy({ $0.isASCII && $0.isNumber }) {
                out += t
            } else if let s = separators[t] {
                out += s
            } else if t == "at", next == "sign" {
                out += "@"; i += 1
            } else {
                return .failure(.unknown(t))
            }
        }
        return capital ? .failure(.capitalWithoutLetter) : .success(out)
    }
}
