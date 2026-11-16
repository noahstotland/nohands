import Foundation

public enum Routing: Equatable, Sendable {
    case execute([Action])
    case resolveWithLLM(String)     // normalized transcript
    case ignore(reason: String)
    /// The grammar recognised the phrase but it can't be run (a `spell` with an unknown word). Shown, never sent to the model.
    case reject(String)
    /// The whole phrase is a macro's name (command mode only; the grammar is asked first). The pipeline runs its steps.
    case macro(Macro)
    /// "forget that route" (`all: false`) or "forget all routes" (`all: true`): route memory is the pipeline's, not the
    /// executor's. Command mode only; never sent to the model.
    case forgetRoutes(all: Bool)
}

public struct ModeMachine: Sendable {
    public private(set) var mode: Mode
    private var grammar: CommandGrammar
    private let attention: AttentionGate
    private let macros: Macros
    private var session = DictationSession()

    public init(grammar: CommandGrammar = CommandGrammar(), mode: Mode = .command, attention: AttentionGate = .off,
                macros: Macros = Macros()) {
        self.grammar = grammar
        self.macros = macros
        self.mode = mode
        self.attention = attention
    }

    /// Routes the next utterance with `grammar`; the mode and any dictation session carry on.
    public mutating func use(grammar: CommandGrammar) { self.grammar = grammar }

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

    /// The transcript without the attention word when the gate is on and the speaker used it.
    private static func addressed(_ transcript: String, attention: AttentionGate) -> String {
        if case .addressed(let rest) = attention.check(transcript) { return rest }
        return transcript
    }

    /// Whole-utterance dictation commands: the escape phrases, "scratch that", "delete word", "delete that" and every
    /// text edit ("select the last sentence", "delete the old files"). A phrase edit counts whether or not a field is
    /// focused: it is never merged with its neighbours, and `route` types the words when there is no field to edit.
    public static func isDictationCommand(_ transcript: String, attention: AttentionGate = .off) -> Bool {
        if isDictationEscape(transcript, attention: attention) { return true }
        let phrase = phrase(transcript, attention: attention)
        if phrase == "scratch that" || phrase == "delete word" || phrase == "delete that" { return true }
        return namesTextEdit(transcript, attention: attention)
    }

    /// True when the words are a text edit that works only in a focused text field (so the caller asks the front app
    /// whether there is one before routing, and not for any other utterance).
    public static func namesTextEdit(_ transcript: String, attention: AttentionGate = .off) -> Bool {
        CommandGrammar.parseEdit(addressed(transcript, attention: attention), textFocused: true) != nil
    }

    /// Drops the "scratch that" record. The pipeline calls it on pause: what was routed may never have been typed,
    /// and the user may edit by hand before resuming, so the record no longer matches the screen.
    public mutating func forgetDictationRecord() { session.forgetLast() }

    /// Applies mode transitions contained in the result and returns what the executor should do. `frontmost` is the
    /// frontmost app's bundle ID, for its pack's phrases in command mode. `textFocused` is whether the front app has a
    /// text field focused: edits that name words in the field need it (without one they go to the model in command mode
    /// and are typed as words in dictation).
    public mutating func route(_ transcript: String, frontmost bundleID: String? = nil, textFocused: Bool = false) -> Routing {
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
            if phrase == "delete that" {
                session.forgetLast()
                return .execute([.pressKey(KeyChord(.delete))])
            }
            if let edit = CommandGrammar.parseEdit(Self.addressed(transcript, attention: attention), textFocused: textFocused) {
                // A fixed edit moves the cursor, so "scratch that" no longer matches the screen. A phrase edit falls back
                // to typing the words when the phrase is not in the field, so its record stays until the pipeline learns
                // the edit ran (`forgetDictationRecord`).
                if !edit.targetsPhrase {
                    session.forgetLast()
                    return .execute([.editText(edit, otherwise: nil)])
                }
                let text = session.next(transcript)
                return text.isEmpty ? .ignore(reason: "empty") : .execute([.editText(edit, otherwise: text)])
            }
            let text = session.next(transcript)
            return text.isEmpty ? .ignore(reason: "empty") : .execute([.typeText(text)])
        case .command:
            // A stop phrase is never gated: it takes the ungated path whatever the gate says.
            if attention.isOn && !StopWords.isStop(transcript) {
                switch attention.check(transcript) {
                case .addressed(let rest): return routeCommand(rest, frontmost: bundleID, textFocused: textFocused)
                case .wordOnly: return .ignore(reason: "attention word only")
                case .notAddressed: return .ignore(reason: "not addressed")
                case .off: break
                }
            }
            return routeCommand(transcript, frontmost: bundleID, textFocused: textFocused)
        }
    }

    /// Routes one macro step: command mode, no attention word (the user wrote it without), and never a macro lookup.
    /// A step that is a macro's name was refused at load; this is the second guard.
    public mutating func routeStep(_ step: String, frontmost bundleID: String? = nil, textFocused: Bool = false) -> Routing {
        guard !CommandGrammar.normalize(step).isEmpty else { return .ignore(reason: "empty") }
        guard mode == .command else { return .ignore(reason: "not in command mode") }
        return routeCommand(step, frontmost: bundleID, textFocused: textFocused, lookUpMacro: false)
    }

    private mutating func routeCommand(_ transcript: String, frontmost bundleID: String?, textFocused: Bool,
                                       lookUpMacro: Bool = true) -> Routing {
        let phrase = CommandGrammar.normalize(transcript).joined(separator: " ")
        if let all = CommandGrammar.forgetsRoutes(phrase) { return .forgetRoutes(all: all) }
        guard let actions = grammar.parse(transcript, frontmost: bundleID, textFocused: textFocused) else {
            if let message = grammar.rejection(transcript) { return .reject(message) }
            if lookUpMacro, let macro = macros.match(transcript) { return .macro(macro) }
            return .resolveWithLLM(phrase)
        }
        for case .setMode(let m) in actions {
            mode = m
            if m == .dictation { session = DictationSession() }
        }
        return .execute(actions)
    }
}
