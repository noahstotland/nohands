import Foundation

public enum Routing: Equatable, Sendable {
    case execute([Action])
    case resolveWithLLM(String)     // normalized transcript
    case ignore(reason: String)
    /// The grammar recognised the phrase but it can't be run (a `spell` with an unknown word). Shown, never sent to the model.
    case reject(String)
}

public struct ModeMachine: Sendable {
    public private(set) var mode: Mode
    private let grammar: CommandGrammar
    private let attention: AttentionGate
    private var session = DictationSession()

    public init(grammar: CommandGrammar = CommandGrammar(), mode: Mode = .command, attention: AttentionGate = .off) {
        self.grammar = grammar
        self.mode = mode
        self.attention = attention
    }

    /// Forces the mode (e.g. an LLM-produced `.setMode`). Idempotent: re-applying the current mode changes
    /// nothing, so an ongoing dictation session is not reset. Entering dictation starts a fresh session.
    public mutating func apply(mode newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        if newMode == .dictation { session = DictationSession() }
    }

    /// The normalized phrase of a transcript; with the gate on, the phrase after the attention word if it is there
    /// (so "computer, stop dictating" counts as "stop dictating"). Mode words work with or without the word.
    private static func phrase(_ transcript: String, attention: AttentionGate) -> String {
        var text = transcript
        if case .addressed(let rest) = attention.check(transcript) { text = rest }
        return CommandGrammar.normalize(text).joined(separator: " ")
    }

    /// The phrases that leave dictation mode ("stop dictating", "command mode").
    public static func isDictationEscape(_ transcript: String, attention: AttentionGate = .off) -> Bool {
        let phrase = phrase(transcript, attention: attention)
        return phrase == "stop dictating" || phrase == "command mode"
    }

    /// Whole-utterance dictation commands: the escape phrases plus "scratch that" and "delete word".
    public static func isDictationCommand(_ transcript: String, attention: AttentionGate = .off) -> Bool {
        if isDictationEscape(transcript, attention: attention) { return true }
        let phrase = phrase(transcript, attention: attention)
        return phrase == "scratch that" || phrase == "delete word"
    }

    /// Drops the "scratch that" record. The pipeline calls it on pause: what was routed may never have been typed,
    /// and the user may edit by hand before resuming, so the record no longer matches the screen.
    public mutating func forgetDictationRecord() { session.forgetLast() }

    /// Applies mode transitions contained in the result and returns what the executor should do. `frontmost` is the
    /// frontmost app's bundle ID, for its pack's phrases in command mode.
    public mutating func route(_ transcript: String, frontmost bundleID: String? = nil) -> Routing {
        let tokens = CommandGrammar.normalize(transcript)
        guard !tokens.isEmpty else { return .ignore(reason: "empty") }
        // Only sleep and dictation read it; command mode checks the gate itself.
        var phrase: String { Self.phrase(transcript, attention: attention) }

        switch mode {
        case .sleep:
            guard phrase == "wake up" else { return .ignore(reason: "sleeping") }
            mode = .command
            return .execute([.setMode(.command)])
        case .dictation:
            if Self.isDictationEscape(transcript, attention: attention) {
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
            // A stop phrase is never gated: it takes the ungated path whatever the gate says.
            if attention.isOn && !StopWords.isStop(transcript) {
                switch attention.check(transcript) {
                case .addressed(let rest): return routeCommand(rest, frontmost: bundleID)
                case .wordOnly: return .ignore(reason: "attention word only")
                case .notAddressed: return .ignore(reason: "not addressed")
                case .off: break
                }
            }
            return routeCommand(transcript, frontmost: bundleID)
        }
    }

    private mutating func routeCommand(_ transcript: String, frontmost bundleID: String?) -> Routing {
        let phrase = CommandGrammar.normalize(transcript).joined(separator: " ")
        guard let actions = grammar.parse(transcript, frontmost: bundleID) else {
            if let message = grammar.rejection(transcript) { return .reject(message) }
            return .resolveWithLLM(phrase)
        }
        for case .setMode(let m) in actions {
            mode = m
            if m == .dictation { session = DictationSession() }
        }
        return .execute(actions)
    }
}
