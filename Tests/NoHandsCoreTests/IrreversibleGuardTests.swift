import Testing
import CoreGraphics
import NoHandsCore

private func el(_ id: Int, _ title: String, role: String = "AXButton", states: [String] = []) -> UIElementInfo {
    UIElementInfo(id: id, frame: CGRect(x: 0, y: id * 40, width: 80, height: 30), title: title, role: role, states: states)
}

@Test func irreversibleStepsAreHeldUntilTheGoalNamesTheVerb() {
    let labels = [1: el(1, "Send"), 2: el(2, "Sender"), 3: el(3, "Sent"), 4: el(4, "Posts"), 5: el(5, "Place order"),
                  6: el(6, "Reload"), 7: el(7, "Pay now"), 8: el(8, "Empty Trash"),
                  9: el(9, "Send", states: ["focused"]), 10: el(10, "Body", role: "AXTextArea", states: ["focused"])]
    func click(_ n: Int) -> [Action] { [.click(.label(n), button: .left, count: 1)] }
    let enter: [Action] = [.pressKey(KeyChord(.return, [.command]))]
    // (actions, labels, goal, the verb asked about or nil)
    let table: [([Action], [Int: UIElementInfo], String, String?)] = [
        (click(1), labels, "reply to Anna", "send"),
        ([.click(.numbered(1), button: .left, count: 1)], labels, "reply to Anna", "send"),
        ([.click(.element(named: "Delete"), button: .left, count: 1)], labels, "tidy up", "delete"),
        ([.clickIn(.sheet, name: "Remove")], labels, "tidy up", "remove"),
        ([.menuItem("Message > Send Again")], labels, "tidy up", "send"),
        ([.setValue(.label(1), "x")], labels, "tidy up", "send"),
        ([.setValue(.named("Submit"), "x")], labels, "tidy up", "submit"),
        ([.click(.element(named: "Check out"), button: .left, count: 1)], labels, "tidy up", "checkout"),
        (click(7), labels, "tidy up", "pay"),
        (click(8), labels, "tidy up", "empty trash"),
        // whole words only; names with no guarded verb; actions with no name
        (click(2), labels, "reply to Anna", nil), (click(3), labels, "reply to Anna", nil),
        (click(4), labels, "reply to Anna", nil), (click(6), labels, "reply to Anna", nil),
        ([.menuItem("Mailbox > Erase Deleted Items")], labels, "tidy up", nil),
        // empty parts of a menu path are dropped, as the executor does: the leaf is the last part with a name
        ([.menuItem("Send>")], labels, "tidy up", "send"), ([.menuItem("Message > Send >> ")], labels, "tidy up", "send"),
        ([.menuItem("Empty Trash >")], labels, "tidy up", "empty trash"), ([.menuItem(" > ")], labels, "tidy up", "unnamed menu item"),
        ([.typeText("send"), .scroll(.down, amount: 3), .click(.point(CGPoint(x: 1, y: 1)), button: .left, count: 1)],
         labels, "reply to Anna", nil),
        // the goal's own verb, in any form, allows it; each verb only by its own forms
        (click(1), labels, "send the reply", nil), (click(1), labels, "sending the email", nil),
        (click(7), labels, "he paid", nil),
        (click(5), labels, "buy a lamp", "place order"), (click(5), labels, "order a lamp", nil),
        (click(8), labels, "empty the trash", nil), (click(8), labels, "empty it", "empty trash"),
        // Return presses the focused button; no focused button or a focused text field is not held
        (enter, labels, "reply to Anna", "send"),
        (enter, labels.filter { $0.key != 9 }, "reply to Anna", nil),
        // the executor matches a partial name ("order" finds "Place order"), so the element it will press is checked
        ([.click(.element(named: "order"), button: .left, count: 1)], labels, "reply to Anna", "place order"),
        ([.click(.element(named: "Sen"), button: .left, count: 1)], labels, "reply to Anna", "send"),
        // only the tier the executor would use: an exact "Subscribe" is not held for an "Unsubscribe" link beside it
        ([.click(.element(named: "Subscribe"), button: .left, count: 1)],
         [1: el(1, "Subscribe"), 2: el(2, "Unsubscribe")], "reply to Anna", nil),
        ([.click(.element(named: "subscribe"), button: .left, count: 1)], [2: el(2, "Unsubscribe")], "reply to Anna", "unsubscribe"),
        // a prefix decoy does not hide the button a "contains" lookup (agent-desktop) would pick
        ([.setChecked(.named("order"), nil)], [1: el(1, "Order history"), 2: el(2, "Place order")], "reply to Anna", "place order"),
        // moving the cursor or focus onto the button is the first half of pressing it
        ([.moveCursor(.label(1))], labels, "reply to Anna", "send"),
        ([.focusElement(.named("Send"))], labels, "reply to Anna", "send"),
        // a negated verb does not allow itself
        (click(1), labels, "reply to Anna but don't send it", "send"), (click(1), labels, "send it, don't delete", nil),
        (click(1), labels, "I don't want to send it", "send"), (click(1), labels, "don't actually send it", "send"),
        (click(1), labels, "no problem, send it", nil), (click(1), labels, "don't wait, send it", nil),
        // a comma ends a negation only when no guarded verb was negated, or a new instruction follows
        (click(1), labels, "no, send it", nil), (click(1), labels, "don't send it, just save", "send"),
        (click(1), labels, "don't delete, send or archive anything", "send"), (click(1), labels, "don't delete it, just send it", nil),
        // every held verb in the step is named, so one yes covers exactly what was asked about
        (click(6) + click(5) + click(1), labels, "reply to Anna", "place order and send"),
        (click(1) + click(1) + click(5), labels, "send it", "place order"),
    ]
    for (actions, labels, goal, expected) in table {
        #expect(IrreversibleGuard.held(actions, labels: labels, goal: goal) == expected, "\(actions) / \(goal)")
    }
}

@Test func everyRouteToAButtonIsHeld() {
    let reload = el(1, "Reload"), send = el(2, "Send"), back = el(3, "Back"), field = el(4, "Body", role: "AXTextArea")
    let labels = [1: reload, 2: send, 3: back, 4: field]
    let atSend = CGPoint(x: 40, y: 95)   // inside Send (y 80...110), not Reload (40...70)
    let grid = OverlayState.grid(GridModel(bounds: CGRect(x: 0, y: 0, width: 80, height: 400), columns: 1, rows: 10))
    func click(_ t: ClickTarget) -> [Action] { [.click(t, button: .left, count: 1)] }
    let focused = ["focused"]
    let focusedSend = [1: reload, 2: el(2, "Send", states: focused)]
    // (actions, overlay, real pointer, labels, the verb asked about or nil)
    let table: [([Action], OverlayState, CGPoint?, [Int: UIElementInfo], String?)] = [
        // a grid cell is the element under its centre, not label n (cell 3 is over Send, cell 2 over Reload)
        (click(.numbered(3)), grid, nil, labels, "send"), (click(.numbered(2)), grid, nil, labels, nil),
        (click(.numbered(1)), .labels([1: send]), nil, labels, "send"), (click(.numbered(2)), .none, nil, labels, "send"),
        // the cursor: moved in this step, already there, moved away, released over the button
        ([.moveCursor(.point(atSend)), click(.cursor)[0]], .none, nil, labels, "send"),
        ([.moveCursor(.relative(dx: 0, dy: 50)), click(.cursor)[0]], .none, CGPoint(x: 40, y: 45), labels, "send"),
        (click(.cursor), .none, atSend, labels, "send"), (click(.cursor), .none, nil, labels, nil),
        ([.moveCursor(.point(CGPoint(x: 900, y: 900))), click(.cursor)[0]], .none, atSend, labels, nil),
        ([.releaseMouse(.left)], .none, atSend, labels, "send"), (click(.point(atSend)), .none, nil, labels, "send"),
        // a drag released on a button presses it
        ([.drag(from: .point(.zero), to: .label(2))], .none, nil, labels, "send"),
        ([.drag(from: .point(.zero), to: .point(atSend))], .none, nil, labels, "send"),
        ([.drag(from: .label(2), to: .point(CGPoint(x: 900, y: 900)))], .none, nil, labels, nil),
        // Space presses a focused button, but not with a modifier or in a text field
        ([.focusElement(.label(2)), .pressKey(KeyChord(.space))], .none, nil, labels, "send"),
        ([.pressKey(KeyChord(.space))], .none, nil, focusedSend, "send"),
        ([.pressKey(KeyChord(.space, [.command]))], .none, nil, focusedSend, nil),
        ([.focusElement(.label(4)), .pressKey(KeyChord(.space))], .none, nil, focusedSend, nil),
    ]
    for (actions, overlay, cursor, labels, expected) in table {
        #expect(IrreversibleGuard.held(actions, labels: labels, goal: "tidy up", overlay: overlay, cursor: cursor) == expected,
                "\(actions) / \(overlay) / \(String(describing: cursor))")
    }
}

@Test func onlyAPlainYesConfirms() {
    let gate = AttentionGate(configured: "computer")
    let table: [(String, Bool)] = [
        ("yes", true), ("Yes.", true), ("confirm", true), ("do it", true), ("yes please", true), ("please do it", true),
        ("yeah", false), ("sure", false), ("no", false), ("", false), ("yes and also open Safari", false), ("stop", false),
    ]
    for (text, expected) in table {
        #expect(ConfirmAnswer.isYes(text, attention: .off) == expected, "\(text)")
    }
    // with an attention word set the yes needs it, so a "yes" from a TV in the room cannot press Send
    let addressed: [(String, Bool)] = [("computer, yes", true), ("computer do it", true), ("yes", false), ("computer", false)]
    for (text, expected) in addressed { #expect(ConfirmAnswer.isYes(text, attention: gate) == expected, "\(text)") }
}
