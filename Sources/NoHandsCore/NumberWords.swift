import Foundation

public enum NumberWords {
    private static let units: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
        "to": 2, "too": 2, "for": 4,
    ]
    private static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Parses a run of tokens as a cardinal number. Accepts digits ("42"), words ("forty two", "one hundred five"),
    /// and in-slot homophones ("to"/"too" → 2, "for" → 4). Returns nil if the tokens are not a number.
    public static func parse(_ tokens: [String]) -> Int? {
        if tokens.count == 1, !tokens[0].isEmpty, tokens[0].allSatisfy({ $0.isASCII && $0.isNumber }) {
            return Int(tokens[0])
        }
        let words = tokens.flatMap { $0.lowercased().split(separator: "-").map(String.init) }
        guard !words.isEmpty else { return nil }

        var total = 0
        var sawAny = false
        var i = 0
        // Grammar: [units] ["hundred" ["and"]] [tens] [units]
        if i < words.count, let u = units[words[i]], i + 1 < words.count, words[i + 1] == "hundred" {
            total = u * 100
            i += 2
            sawAny = true
            if i == words.count { return total }
            if words[i] == "and", i + 1 < words.count { i += 1 }
        } else if i < words.count, words[i] == "hundred" {
            total = 100
            i += 1
            sawAny = true
            if i == words.count { return total }
            if words[i] == "and", i + 1 < words.count { i += 1 }
        }
        var rest = 0
        var restAny = false
        if i < words.count, let t = tens[words[i]] {
            rest = t
            i += 1
            restAny = true
            if i < words.count, let u = units[words[i]], u >= 1, u < 10 {
                rest += u
                i += 1
            }
        } else if i < words.count, let u = units[words[i]], u != 0 || !sawAny {
            rest = u
            i += 1
            restAny = true
        }
        guard i == words.count, sawAny || restAny else { return nil }
        return total + rest
    }

    /// Longest prefix of `tokens` that parses as a number, with the remainder.
    /// Homophones ("to", "too", "for") count as numbers, so ["to", "fit"] yields (2, ["fit"]).
    /// Only call this where a number is expected, never on arbitrary text.
    public static func leadingNumber(in tokens: [String]) -> (value: Int, rest: [String])? {
        var n = tokens.count
        while n > 0 {
            if let v = parse(Array(tokens[0..<n])) { return (v, Array(tokens[n...])) }
            n -= 1
        }
        return nil
    }
}
