import Foundation

/// A named sequence of steps (config key `macros`): say the name and each step runs in order as if it had been spoken.
public struct Macro: Equatable, Sendable {
    /// The phrase to say, normalized (lower case, no `.,!?`).
    public var name: String
    /// Each step as the user would say it, without the attention word.
    public var steps: [String]
}

/// The user's macros. Pure text; decoding never fails: a bad macro is skipped whole and counted in `skipped`.
public struct Macros: Codable, Equatable, Sendable {
    public static let maxMacros = 50
    public static let maxNameWords = 6
    public static let maxSteps = 20
    public static let maxStepCharacters = 200

    /// The kept macros, in name order.
    public private(set) var all: [Macro]
    /// How many config macros were dropped (never their names or steps).
    public private(set) var skipped: Int

    public init() { all = []; skipped = 0 }
    /// An empty set that counts a `macros` value that was not an object as one skipped macro.
    init(skipped: Int) { all = []; self.skipped = skipped }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Lossy<[String]>].self)
        let named = raw.map { (name: CommandGrammar.normalize($0.key).joined(separator: " "), steps: $0.value.value) }
        // Two spellings of one name: there is no "first" to prefer (the decoder keeps no key order), so neither runs.
        let copies = Dictionary(grouping: named, by: \.name).mapValues(\.count)
        let grammar = CommandGrammar()
        var kept: [Macro] = []
        for (name, steps) in named {
            guard copies[name] == 1, let steps, Self.nameIsUsable(name, grammar: grammar),
                  Self.stepsAreUsable(steps, names: Set(copies.keys)) else { continue }
            kept.append(Macro(name: name, steps: steps.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
        }
        all = Array(kept.sorted { $0.name < $1.name }.prefix(Self.maxMacros))
        skipped = raw.count - all.count
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.steps) }))
    }

    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    }

    /// Not empty, short, no stop word, and not a phrase the grammar or the route commands already own (it would never be reached).
    private static func nameIsUsable(_ name: String, grammar: CommandGrammar) -> Bool {
        guard !name.isEmpty, name.split(separator: " ").count <= maxNameWords, !Vocabulary.hasStopWord(name) else { return false }
        return grammar.parse(name) == nil && grammar.rejection(name) == nil && CommandGrammar.forgetsRoutes(name) == nil
    }

    /// Every step is short, has no stop word, does not change mode and is not a macro name (no recursion).
    private static func stepsAreUsable(_ steps: [String], names: Set<String>) -> Bool {
        guard (1...maxSteps).contains(steps.count) else { return false }
        return steps.allSatisfy { step in
            let phrase = CommandGrammar.normalize(step).joined(separator: " ")
            return !phrase.isEmpty && step.count <= maxStepCharacters && !Vocabulary.hasStopWord(step)
                && !CommandGrammar.isReservedGlobal(phrase) && !names.contains(phrase)
        }
    }

    /// The macro the whole transcript names, or nil. Case and `.,!?` do not matter; extra words do.
    public func match(_ transcript: String) -> Macro? {
        let phrase = CommandGrammar.normalize(transcript).joined(separator: " ")
        return all.first { $0.name == phrase }
    }
}
