import Testing
@testable import NoHandsCore

@Test func statusBarLine() {
    let t0 = ContinuousClock.now
    func row(_ id: Int, _ text: String, _ status: PromptStatus, at s: Int = 0) -> PromptRow {
        PromptRow(id: id, text: text, status: status, updatedAt: t0.advanced(by: .seconds(s)))
    }
    func line(_ menu: MenuState = .listening, _ mode: Mode = .command, _ rows: [PromptRow] = []) -> String? {
        StatusBarText.line(menu: menu, mode: mode, rows: rows)?.text
    }
    let running = row(1, "open youtube", .running("step 2 · type"))
    #expect(line() == nil)
    #expect(line(.listening, .sleep) == "Asleep · say wake up")
    #expect(line(.listening, .dictation) == "Dictating · say stop dictating")
    #expect(line(.loading) == "Loading speech model…")
    // a running task shows its goal and step
    #expect(line(.listening, .command, [running]) == "open youtube · step 2 · type")
    // running beats a newer held / heard prompt
    #expect(line(.listening, .command, [running, row(2, "next", .held, at: 5)]) == "open youtube · step 2 · type")
    // a live row beats a final one; a final one beats idle
    #expect(line(.listening, .command, [row(3, "old", .done("done"), at: 9), row(4, "now", .heard, at: 1)]) == "now · heard")
    #expect(line(.listening, .command, [row(5, "a", .done("done"), at: 1), row(6, "b", .stopped(""), at: 2)]) == "b · stopped")
    // problems and pause outrank a running row
    #expect(line(.needsAccessibility, .command, [running])?.hasPrefix("Needs Accessibility") == true)
    #expect(line(.microphoneDenied)?.hasPrefix("Microphone denied") == true)
    #expect(line(.error("boom"), .command, [running]) == "Error: boom · choose Retry in the menu")
    #expect(line(.paused, .command, [row(7, "x", .stopped(""))])?.hasPrefix("Paused") == true)
    #expect(StatusBarText.line(menu: .listening, mode: .command, rows: [running])?.tone == .active)
}

@Test func statusBarPositionStored() {
    let expected: [(String?, StatusBarPosition)] = [
        (nil, .corner), ("", .corner), ("top", .corner), ("bottom", .corner),
        ("middle", .corner), ("corner", .corner), ("off", .off),
    ]
    for (raw, position) in expected { #expect(StatusBarPosition.stored(raw) == position) }
}
