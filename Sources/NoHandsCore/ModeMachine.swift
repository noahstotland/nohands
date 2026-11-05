import Foundation

public enum Routing: Equatable, Sendable {
    case execute([Action])
    case resolveWithLLM(String)     // normalized transcript
    case ignore(reason: String)
}

public struct ModeMachine: Sendable {
    public private(set) var mode: Mode
    private let grammar: CommandGrammar
    private var session = DictationSession()

    public init(grammar: CommandGrammar = CommandGrammar(), mode: Mode = .command) {
        self.grammar = grammar
        self.mode = mode
    }

    /// Forces the mode (e.g. an LLM-produced `.setMode`). Idempotent: re-applying the current mode changes
    /// nothing, so an ongoing dictation session is not reset. Entering dictation starts a fresh session.
    public mutating func apply(mode newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .dictation { session = DictationSession() }
    }

    /// The phrases that leave dictation mode ("stop dictating", "command mode").
    public static func isDictationEscape(_ transcript: String) -> Bool {
        let phrase = CommandGrammar.normalize(transcript).joined(separator: " ")
        return phrase == "stop dictating" || phrase == "command mode"
    }

    /// Whole-utterance dictation commands: the escape phrases plus "scratch that" and "delete word".
    public static func isDictationCommand(_ transcript: String) -> Bool {
        if isDictationEscape(transcript) { return true }
        let phrase = CommandGrammar.normalize(transcript).joined(separator: " ")
        return phrase == "scratch that" || phrase == "delete word"
    }

    /// Applies mode transitions contained in the result and returns what the executor should do.
    public mutating func route(_ transcript: String) -> Routing {
        let tokens = CommandGrammar.normalize(transcript)
        guard !tokens.isEmpty else { return .ignore(reason: "empty") }
        let phrase = tokens.joined(separator: " ")

        switch mode {
        case .sleep:
            guard phrase == "wake up" else { return .ignore(reason: "sleeping") }
            mode = .command
            return .execute([.setMode(.command)])
        case .dictation:
            if Self.isDictationEscape(phrase) {
                mode = .command
                return .execute([.setMode(.command)])
            }
            if phrase == "scratch that" {
                guard let n = session.scratch() else { return .ignore(reason: "nothing to scratch") }
                return .execute(Array(repeating: .pressKey(KeyChord(.delete)), count: n))
            }
            if phrase == "delete word" {
                session.forgetLast()
                return .execute([.pressKey(KeyChord(.delete, [.option]))])
            }
            let text = session.next(transcript)
            return text.isEmpty ? .ignore(reason: "empty") : .execute([.typeText(text)])
        case .command:
            guard let actions = grammar.parse(transcript) else { return .resolveWithLLM(phrase) }
            for case .setMode(let m) in actions {
                mode = m
                if m == .dictation { session = DictationSession() }
            }
            return .execute(actions)
        }
    }
}
