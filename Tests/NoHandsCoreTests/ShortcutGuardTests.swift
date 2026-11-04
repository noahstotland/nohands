import Testing
@testable import NoHandsCore

@Test func commandWBlockedWhenGoalDoesNotAskToClose() {
    let msg = ShortcutGuard.blocked([.pressKey(KeyChord(.w, [.command])), .typeText("x")], goal: "open the latest video")
    #expect(msg == "blocked: command-w not allowed for this request")
    #expect(ShortcutGuard.blocked([.pressKey(KeyChord(.w, [.command, .shift]))], goal: "open the latest video") != nil)
    #expect(ShortcutGuard.blocked([.pressKey(KeyChord(.q, [.command]))], goal: "play music") == "blocked: command-q not allowed for this request")
}

@Test func closeOrQuitGoalsAllowTheChord() {
    #expect(ShortcutGuard.blocked([.pressKey(KeyChord(.w, [.command]))], goal: "close this tab") == nil)
    #expect(ShortcutGuard.blocked([.openApp("Spotify"), .pressKey(KeyChord(.q, [.command]))], goal: "Quit Spotify.") == nil)
    #expect(ShortcutGuard.blocked([.pressKey(KeyChord(.q, [.command]))], goal: "shut down slack") == nil)
}

@Test func plainWAndOtherChordsAreAllowed() {
    #expect(ShortcutGuard.blocked([.pressKey(KeyChord(.w, []))], goal: "open the latest video") == nil)
    #expect(ShortcutGuard.blocked([.pressKey(KeyChord(.l, [.command])), .typeText("w")], goal: "open the latest video") == nil)
    #expect(ShortcutGuard.blocked([], goal: "x") == nil)
}
