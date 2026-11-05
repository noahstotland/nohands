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

@Test func summaryOfHarnessActionsOmitsPayloads() {
    let s = ActionSummary.kinds([
        .setValue(.label(1), "secret"), .typeInto(.named("Search"), "hi"), .clearField(.label(1)),
        .selectOption(.label(2), "Blue"), .setChecked(.label(3), nil), .setExpanded(.label(4), true),
        .focusElement(.label(5)), .scrollTo(.label(6)), .scrollIn(.label(7), .down, amount: 3),
        .drag(from: .label(1), to: .point(.zero)), .clickIn(.dock, name: "Safari"), .menuItem("Save As…"),
        .closeApp("Slack"), .windowAction(.minimize, app: "Slack", title: nil), .clipboardSet("pw"),
        .readClipboard, .readValue(.label(1)), .readNotifications, .dismissNotifications(app: "Mail"),
        .waitFor(.text("done"), timeoutMs: 1000)])
    #expect(s == "[setValue(len=6), typeInto(len=2), clearField, selectOption, setChecked, setExpanded, focusElement, scrollTo, scrollIn, drag, clickIn(dock), menuItem, closeApp, windowAction(minimize), clipboardSet(len=2), readClipboard, readValue, readNotifications, dismissNotifications, waitFor(text)]")
    for leak in ["secret", "Search", "Blue", "Safari", "Save", "Slack", "pw", "Mail", "done"] { #expect(!s.contains(leak)) }
}
