import Testing
import Foundation
@testable import NoHandsCore

@Test func commandModeRoutesGrammarThenLLM() {
    var m = ModeMachine()
    #expect(m.route("click") == .execute([.click(.cursor, button: .left, count: 1)]))
    #expect(m.route("make the window bigger") == .resolveWithLLM("make the window bigger"))
    #expect(m.route("   ") == .ignore(reason: "empty"))
}

@Test func dictationModeTypesEverythingExceptExit() {
    var m = ModeMachine()
    #expect(m.route("start dictating") == .execute([.setMode(.dictation)]))
    #expect(m.mode == .dictation)
    #expect(m.route("click save period") == .execute([.typeText("Click save.")]))
    #expect(m.route("stop dictating") == .execute([.setMode(.command)]))
    #expect(m.mode == .command)
}

@Test func sleepIgnoresAllButWakeUp() {
    var m = ModeMachine()
    _ = m.route("go to sleep")
    #expect(m.mode == .sleep)
    #expect(m.route("click") == .ignore(reason: "sleeping"))
    #expect(m.route("make it bigger") == .ignore(reason: "sleeping"))
    #expect(m.route("wake up") == .execute([.setMode(.command)]))
    #expect(m.mode == .command)
}

@Test func dictationSessionSpacingPersistsAcrossRoutes() {
    var m = ModeMachine()
    _ = m.route("start dictating")
    #expect(m.route("hello") == .execute([.typeText("Hello")]))
    #expect(m.route("world") == .execute([.typeText(" world")]))
}

@Test func applyModeIsIdempotentAndKeepsDictationSession() {
    var m = ModeMachine()
    _ = m.route("start dictating")
    #expect(m.route("hello there") == .execute([.typeText("Hello there")]))
    m.apply(mode: .dictation)   // same mode: must not reset session spacing
    #expect(m.route("again") == .execute([.typeText(" again")]))
}

@Test func applyModeSyncsMachineAndResetsSessionOnEnteringDictation() {
    var m = ModeMachine()
    m.apply(mode: .dictation)
    #expect(m.mode == .dictation)
    #expect(m.route("hello") == .execute([.typeText("Hello")]))
    m.apply(mode: .command)
    m.apply(mode: .dictation)   // fresh session: capitalized, no leading space
    #expect(m.route("world") == .execute([.typeText("World")]))
    m.apply(mode: .sleep)
    #expect(m.route("click") == .ignore(reason: "sleeping"))
}

@Test func dictationEscapePhrases() {
    #expect(ModeMachine.isDictationEscape("Stop dictating."))
    #expect(ModeMachine.isDictationEscape("command mode"))
    #expect(!ModeMachine.isDictationEscape("stop"))
    #expect(!ModeMachine.isDictationEscape("please stop dictating now"))
}

@Test func dictationCommandPhrases() {
    for t in ["Scratch that.", "delete word", "stop dictating", "command mode", "Delete that."] { #expect(ModeMachine.isDictationCommand(t), "\(t)") }
    for t in ["I said scratch that", "scratch", "I will delete that", "select all", "delete"] { #expect(!ModeMachine.isDictationCommand(t), "\(t)") }
    var m = ModeMachine()   // command mode is unchanged
    #expect(m.route("delete word") == .execute([.pressKey(KeyChord(.delete, [.option]))]))
    #expect(m.route("scratch that") == .resolveWithLLM("scratch that"))
}

@Test func scratchThatDeletesExactlyWhatTheLastUtteranceTyped() {
    let nothing = Routing.ignore(reason: "nothing to scratch")
    let table: [([String], Int)] = [
        (["hello"], 5),                                     // "Hello"
        (["hello", "world period"], 7),                     // " world." leading space and punctuation
        (["hello", "new paragraph"], 2),                    // "\n\n" counts as two
    ]
    for (spoken, n) in table {
        var m = ModeMachine(mode: .dictation)
        for s in spoken { _ = m.route(s) }
        #expect(m.route("scratch that") == .execute(Array(repeating: .pressKey(KeyChord(.delete)), count: n)), "\(spoken)")
        #expect(m.route("scratch that") == nothing, "\(spoken)")   // one level only
    }
    var m = ModeMachine(mode: .dictation)
    #expect(m.route("scratch that") == nothing)
    _ = m.route("hello period"); _ = m.route("world period"); _ = m.route("scratch that")
    #expect(m.route("there") == .execute([.typeText(" There")]))   // context restored to "Hello."
    _ = m.route("delete word")                                      // clears the record
    #expect(m.route("scratch that") == nothing)
    _ = m.route("again")
    m.forgetDictationRecord()                                       // pause: the screen may have changed
    #expect(m.route("scratch that") == nothing)
}

@Test func attentionWordGatesCommandModeOnly() {
    var m = ModeMachine(attention: AttentionGate(configured: "computer"))
    let click = Routing.execute([.click(.cursor, button: .left, count: 1)])
    let table: [(String, Routing)] = [
        ("computer click", click),
        ("Computer, make the window bigger.", .resolveWithLLM("make the window bigger")),   // the model never sees the word
        ("click", .ignore(reason: "not addressed")),
        ("computer", .ignore(reason: "attention word only")),
        ("tell the computer to click", .ignore(reason: "not addressed")),
        ("stop", .resolveWithLLM("stop")),   // a stop is never gated; the pipeline turns it into a stop or an ignore
        ("computer, stop", .resolveWithLLM("stop")),
    ]
    for (said, expected) in table {
        #expect(m.route(said) == expected, "\(said)")
    }

    // Dictation types everything; the mode words work with or without the word, other text starting with it is typed.
    #expect(m.route("computer, start dictating") == .execute([.setMode(.dictation)]))
    #expect(m.mode == .dictation)
    #expect(m.route("computer hello") == .execute([.typeText("Computer hello")]))
    #expect(m.route("stop dictating") == .execute([.setMode(.command)]))
    _ = m.route("computer start dictating")
    #expect(m.route("computer, stop dictating") == .execute([.setMode(.command)]))

    // Sleep: "go to sleep" needs the word; "wake up" works without it.
    #expect(m.route("go to sleep") == .ignore(reason: "not addressed"))
    #expect(m.route("computer go to sleep") == .execute([.setMode(.sleep)]))
    #expect(m.route("click") == .ignore(reason: "sleeping"))
    #expect(m.route("wake up") == .execute([.setMode(.command)]))
}

@Test func textEditsWhileDictating() {
    func edit(_ e: TextEdit, _ otherwise: String? = nil) -> Routing { .execute([.editText(e, otherwise: otherwise)]) }
    // Fixed edits (units, caret, case) never carry text; phrase edits carry what dictation would have typed.
    let table: [(String, Bool, Routing)] = [
        ("select the last sentence", true, edit(.select(.sentence, last: true))),
        ("select the last sentence", false, edit(.select(.sentence, last: true))),
        ("Delete line.", true, edit(.delete(.line, last: false))),
        ("go to the end of the line", true, edit(.caret(.lineEnd))),
        ("capitalize that", true, edit(.changeCase(.capitalize))),
        ("Delete the old files.", true, edit(.deletePhrase("the old files"), "Delete the old files.")),
        ("replace meeting with call", true, edit(.replace("meeting", with: "call"), "Replace meeting with call")),
        ("go after thanks", true, edit(.caretAfter("thanks"), "Go after thanks")),
        // No focused field: a phrase is just words, as before.
        ("Delete the old files.", false, .execute([.typeText("Delete the old files.")])),
        ("replace meeting with call", false, .execute([.typeText("Replace meeting with call")])),
        // Unchanged in dictation.
        ("delete that", true, .execute([.pressKey(KeyChord(.delete))])),
        ("delete word", true, .execute([.pressKey(KeyChord(.delete, [.option]))])),
        ("select all", true, .execute([.typeText("Select all")])),
        ("hello there", true, .execute([.typeText("Hello there")])),
    ]
    for (said, focused, expected) in table {
        var m = ModeMachine(mode: .dictation)
        #expect(m.route(said, textFocused: focused) == expected, "\(said) focused=\(focused)")
    }
    // The attention word is ignored when it addresses an edit, like the mode words.
    var gated = ModeMachine(mode: .dictation, attention: AttentionGate(configured: "computer"))
    #expect(gated.route("computer select the last word") == edit(.select(.word, last: true)))
    #expect(ModeMachine.isDictationCommand("computer, delete the old files", attention: AttentionGate(configured: "computer")))
}

@Test func anEditDropsTheScratchRecordOnlyWhenItRan() {
    let nothing = Routing.ignore(reason: "nothing to scratch")
    let backspaces = { (n: Int) in Routing.execute(Array(repeating: .pressKey(KeyChord(.delete)), count: n)) }
    // A fixed edit moves the cursor: "scratch that" must not delete characters at the new place.
    var m = ModeMachine(mode: .dictation)
    _ = m.route("hello"); _ = m.route("select the last word")
    #expect(m.route("scratch that") == nothing)
    // A phrase edit may fall back to typing its words, so "scratch that" still matches until the pipeline says it ran.
    m = ModeMachine(mode: .dictation)
    _ = m.route("hello"); _ = m.route("delete the old files", textFocused: true)
    #expect(m.route("scratch that") == backspaces(21))   // " Delete the old files"
    m = ModeMachine(mode: .dictation)
    _ = m.route("hello"); _ = m.route("delete the old files", textFocused: true); m.forgetDictationRecord()
    #expect(m.route("scratch that") == nothing)
    // Command mode passes the flag to the grammar.
    m = ModeMachine()
    #expect(m.route("delete the old files") == .resolveWithLLM("delete the old files"))
    #expect(m.route("delete the old files", textFocused: true) == .execute([.editText(.deletePhrase("the old files"), otherwise: nil)]))
    #expect(m.route("select the last sentence") == .execute([.editText(.select(.sentence, last: true), otherwise: nil)]))
}

@Test func macroNameRoutesInCommandModeOnly() throws {
    let macros = try AppConfig.load(from: Data(#"{"macros":{"night game":["open chrome","click"]}}"#.utf8), environment: [:]).macros
    let night = Routing.macro(Macro(name: "night game", steps: ["open chrome", "click"]))
    // (attention word, mode, said, routes)
    let table: [(String, Mode, String, Routing)] = [
        ("", .command, "Night game.", night),
        ("", .command, "night game please", .resolveWithLLM("night game please")),
        ("", .command, "click", .execute([.click(.cursor, button: .left, count: 1)])),            // the grammar wins
        ("computer", .command, "computer, night game", night),
        ("computer", .command, "night game", .ignore(reason: "not addressed")),
        ("", .dictation, "night game", .execute([.typeText("Night game")])),
        ("", .sleep, "night game", .ignore(reason: "sleeping")),
    ]
    for (word, mode, said, expected) in table {
        var m = ModeMachine(mode: mode, attention: AttentionGate(configured: word), macros: macros)
        #expect(m.route(said) == expected, "\(word) \(mode) \(said)")
    }
    var m = ModeMachine(attention: AttentionGate(configured: "computer"), macros: macros)
    #expect(m.routeStep("night game") == .resolveWithLLM("night game"))   // a step never expands a macro or needs the word
    #expect(m.routeStep("click") == .execute([.click(.cursor, button: .left, count: 1)]))
}
