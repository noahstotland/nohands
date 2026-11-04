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
