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
            if phrase == "stop dictating" || phrase == "command mode" {
                mode = .command
                return .execute([.setMode(.command)])
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
