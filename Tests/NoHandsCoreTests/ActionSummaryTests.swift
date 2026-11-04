import Testing
@testable import NoHandsCore

@Test func actionSummaryOmitsPayloads() {
    let actions: [Action] = [
        .typeText("my secret password"),
        .click(.element(named: "Send Payment"), button: .left, count: 1),
        .moveCursor(.element(named: "Bank Login")),
        .openApp("1Password"),
        .pressKey(KeyChord(.return, [.command])),
        .setMode(.dictation),
    ]
    let s = ActionSummary.kinds(actions)
    #expect(s == "[typeText(len=18), click, moveCursor, openApp, pressKey, setMode(dictation)]")
    for leak in ["secret", "password", "Send", "Payment", "Bank", "Login", "1Password", "return", "command"] {
        #expect(!s.contains(leak))
    }
}
