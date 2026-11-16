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

@Test func guardMatchesWholeWordsPerKey() {
    let cmdQ: [Action] = [.pressKey(KeyChord(.q, [.command]))], cmdW: [Action] = [.pressKey(KeyChord(.w, [.command]))]
    #expect(ShortcutGuard.blocked(cmdQ, goal: "scroll down quite a bit") != nil)
    #expect(ShortcutGuard.blocked(cmdW, goal: "open the closet photos") != nil)
    #expect(ShortcutGuard.blocked(cmdW, goal: "closing the tab") == nil)
    #expect(ShortcutGuard.blocked(cmdQ, goal: "close this tab") == "blocked: command-q not allowed for this request")
    #expect(ShortcutGuard.blocked(cmdW, goal: "quit Spotify") == "blocked: command-w not allowed for this request")
    #expect(ShortcutGuard.blocked(cmdQ, goal: "exit the app") == nil)
}

@Test func closeAppBlockedUnlessGoalAsksToQuitOrClose() {
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "open slack") == "blocked: close_app not allowed for this request")
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "quit slack") == nil)
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "close slack") == nil)
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "shut down slack") == nil)
    #expect(ShortcutGuard.blocked([.closeApp("Slack")], goal: "the closet app") != nil)
    #expect(ShortcutGuard.blocked([.windowAction(.minimize, app: "Slack", title: nil)], goal: "hide it") == nil)
}

@Test func menuItemsThatCloseOrQuitNeedTheGoalToAskLikeTheChords() {
    // (title, goal, blocked)
    let cases: [(String, String, Bool)] = [
        ("Quit Google Chrome", "play music", true), ("File > Close Window", "open the latest video", true),
        ("Close Tab", "close this tab", false), ("Quit Spotify", "quit spotify", false),
        ("Bookmark This Tab…", "open the latest video", false),
        ("File>Close Window", "open the latest video", true), ("Safari>Quit Safari", "play music", true),
        ("Close…", "play music", true), ("Exit Full Screen", "watch it small", false),
        ("Reopen Closed Tab", "open the latest video", false),
    ]
    for (title, goal, blocked) in cases {
        #expect((ShortcutGuard.blocked([.menuItem(title)], goal: goal) != nil) == blocked, Comment(rawValue: title))
    }
}

@Test func aNegatedQuitOrCloseWordAllowsNothing() {
    let cmdQ: [Action] = [.pressKey(KeyChord(.q, [.command]))], cmdW: [Action] = [.pressKey(KeyChord(.w, [.command]))]
    // (actions, goal, blocked)
    let cases: [([Action], String, Bool)] = [
        (cmdQ, "don't quit Safari", true), (cmdW, "never close this", true), ([.closeApp("Safari")], "don't quit", true),
        ([.menuItem("Close Window")], "don't close it", true),
        (cmdQ, "quit Safari", false), (cmdW, "close this tab", false), (cmdQ, "don't save, just quit", false),
    ]
    for (actions, goal, blocked) in cases { #expect((ShortcutGuard.blocked(actions, goal: goal) != nil) == blocked, Comment(rawValue: goal)) }
    #expect(!ShortcutGuard.allowsClose(goal: "don't close the tabs") && ShortcutGuard.allowsClose(goal: "close the tabs"))
}
