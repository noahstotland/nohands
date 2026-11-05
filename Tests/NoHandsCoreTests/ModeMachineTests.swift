import Testing
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
    for t in ["Scratch that.", "delete word", "stop dictating", "command mode"] { #expect(ModeMachine.isDictationCommand(t), "\(t)") }
    for t in ["I said scratch that", "delete word count", "scratch"] { #expect(!ModeMachine.isDictationCommand(t), "\(t)") }
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
}
