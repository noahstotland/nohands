import Testing
@testable import NoHandsCore

@Test func permissionStatusDecidesTheNextStep() {
    let table: [(Int, AutomationAccess.Step, String?)] = [
        (0, .run, nil), (-1744, .ask, AutomationAccess.allowLine), (-1743, .denied, AutomationAccess.deniedLine),
        (-600, .startSystemEvents, AutomationAccess.startFailedLine), (-1750, .failed(-1750), "couldn't change dark mode (error -1750)"),
    ]
    for (status, step, line) in table {
        #expect(AutomationAccess.step(status: status) == step, "\(status)")
        #expect(AutomationAccess.line(for: step) == line, "\(status)")
    }
}

@Test func scriptAndShortcutResultsBecomeRowLines() {
    let denied = "execution error: Not authorized to send Apple events to System Events. (-1743)"
    let table: [(ChildResult, String)] = [
        (.exited(0, "true\n"), "dark mode"), (.exited(0, "false\n"), "light mode"), (.exited(0, "maybe"), "couldn't change dark mode (error 0)"),
        (.exited(1, denied), AutomationAccess.deniedLine), (.exited(1, "execution error: boom (-10004)"), "couldn't change dark mode (error -10004)"),
        (.exited(2, "no code"), "couldn't change dark mode (error 2)"),
        (.timedOut, AutomationAccess.timeoutLine), (.couldNotStart, "couldn't change dark mode (error -1)"),
    ]
    for (result, line) in table {
        switch AutomationAccess.outcome(result) {
        case .success(let now): #expect(AutomationAccess.doneLine(now) == line, "\(result)")
        case .failure(let failure): #expect(failure.line == line, "\(result)")
        }
    }
    // (shortcut result, `shortcuts list` output, line for "NoHands Do Not Disturb On")
    let on = "NoHands Do Not Disturb On"
    let shortcuts: [(ChildResult, String?, String?)] = [
        (.exited(0, ""), nil, nil), (.timedOut, nil, DoNotDisturb.timeoutLine),
        (.exited(1, ""), "Other\n\(on)\n", "the \(on) shortcut failed"), (.exited(1, ""), "Other\n\(on) copy\n", "no shortcut called \(on): make it in Shortcuts"),
        (.couldNotStart, nil, "the \(on) shortcut failed"),
    ]
    for (result, list, line) in shortcuts { #expect(DoNotDisturb.failure(result, on: true, list: list) == line, "\(result)") }
    #expect(DoNotDisturb.shortcutName(on: false) == "NoHands Do Not Disturb Off")
}
