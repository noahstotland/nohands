import Testing
@testable import NoHandsCore

private let t0 = ContinuousClock.now

private func row(_ id: Int, _ text: String, _ status: PromptStatus, _ trail: TaskTrail? = nil, at s: Int = 0) -> PromptRow {
    PromptRow(id: id, text: text, status: status, updatedAt: t0.advanced(by: .seconds(s)), trail: trail)
}

/// A trail with the given steps: "ok" ends done, "bad" ends failed, "run" stays running.
private func trail(_ steps: [(String, String)], max: Int = 12, ending: TaskTrail.Ending? = nil) -> TaskTrail {
    var t = TaskTrail(maxSteps: max)
    for (i, (intent, how)) in steps.enumerated() {
        t.begin(number: i + 1, intent: intent)
        if how == "ok" { t.end(number: i + 1, failure: nil) }
        if how == "bad" { t.end(number: i + 1, failure: "no field") }
    }
    t.ending = ending
    return t
}

@Test func taskPanelContent() {
    typealias Mark = TaskPanelContent.Mark
    struct Case {
        let name: String
        let row: PromptRow
        let marks: [Mark]
        let progress: String?
        let footer: String?
        let tone: PromptStatus.Tone?
    }
    let running = PromptStatus.running("step 2 · b")
    let two = [("a", "ok"), ("b", "run")]
    let long = String(repeating: "x", count: 90)
    let cases: [Case] = [
        Case(name: "running a step", row: row(1, "p", running, trail(two)), marks: [.done, .current],
             progress: "step 2 of 12", footer: nil, tone: nil),
        Case(name: "between steps", row: row(1, "p", running, trail([("a", "ok")])), marks: [.done],
             progress: "step 1 of 12", footer: "Working out the next step…", tone: .active),
        Case(name: "a failed step, task goes on", row: row(1, "p", running, trail([("a", "bad")])), marks: [.failed],
             progress: "step 1 of 12", footer: "Working out the next step…", tone: .active),
        Case(name: "done", row: row(1, "p", .done("done · p (3 steps)"), trail([("a", "ok"), ("b", "ok"), ("c", "run")])),
             marks: [.done, .done, .done], progress: "step 3 of 12", footer: "done · p (3 steps)", tone: .good),
        Case(name: "step cap", row: row(1, "p", .failed("gave up"), trail([("a", "ok")], ending: .stepCap)),
             marks: [.done], progress: "step 12 of 12", footer: "Hit the 12-step limit · try a smaller request", tone: .bad),
        Case(name: "stuck", row: row(1, "p", .failed("not sure"), trail([("a", "ok")], ending: .stuck)),
             marks: [.done], progress: "step 1 of 12", footer: "not sure · say it another way", tone: .bad),
        Case(name: "resolver error", row: row(1, "p", .failed("model timed out"), trail([("a", "ok"), ("b", "run")])),
             marks: [.done, .failed], progress: "step 2 of 12", footer: "model timed out · try again", tone: .bad),
        Case(name: "resolver error before any step", row: row(1, "p", .failed("model timed out"), trail([])),
             marks: [], progress: nil, footer: "model timed out · try again", tone: .bad),
        Case(name: "grammar failure", row: row(1, "p", .failed("no such window")), marks: [], progress: nil,
             footer: "no such window", tone: .bad),
        Case(name: "stopped mid-step", row: row(1, "p", .stopped("stopped"), trail(two)), marks: [.done, .stopped],
             progress: "step 2 of 12", footer: "stopped", tone: .muted),
        Case(name: "held", row: row(1, "p", .held), marks: [], progress: nil, footer: PromptStatus.held.text, tone: .waiting),
        Case(name: "listening", row: row(1, "p", .listening), marks: [], progress: nil, footer: "listening…", tone: .active),
        Case(name: "heard", row: row(1, "p", .heard), marks: [], progress: nil, footer: "heard", tone: .active),
        Case(name: "live, empty trail", row: row(1, "p", running, trail([])), marks: [], progress: nil,
             footer: "Working out the next step…", tone: .active),
        Case(name: "dropped", row: row(1, "p", .dropped("waited too long")), marks: [], progress: nil,
             footer: "waited too long", tone: .bad),
    ]
    for c in cases {
        let content = TaskPanelText.content(rows: [c.row])
        #expect(content?.phrase == "p", "\(c.name)")
        #expect(content?.lines.map(\.mark) == c.marks, "\(c.name)")
        #expect(content?.progress?.label == c.progress, "\(c.name)")
        #expect(content?.footer?.text == c.footer, "\(c.name)")
        #expect(content?.footer?.tone == c.tone, "\(c.name)")
    }

    // A failed step reads "<intent> · <failure>", a blank intent shows its number, a long one is cut to 80.
    let odd = TaskPanelText.content(rows: [row(1, "p", running, trail([("click", "bad"), ("  ", "ok"), (long, "ok")]))])
    #expect(odd?.lines.map(\.text) == ["click · no field", "step 2", String(repeating: "x", count: 79) + "…"])
    // A long failure is cut too.
    var t = TaskTrail(maxSteps: 5)
    t.begin(number: 1, intent: "click")
    t.end(number: 1, failure: long)
    let cut = TaskPanelText.content(rows: [row(1, "p", running, t)])?.lines.first?.text
    #expect(cut?.count == 80)
    #expect(cut?.hasPrefix("click · xxx") == true)
}

@Test func taskPanelLines() {
    let steps = (1...11).map { ("step\($0)", "ok") }
    let c = TaskPanelText.content(rows: [row(1, "p", .running("step 11 · x"), trail(steps))])
    #expect(c?.lines.count == 8)
    #expect(c?.earlierSteps == 3)
    #expect(c?.lines.first?.text == "step4")
    #expect(c?.lines.last?.text == "step11")
    #expect(abs((c?.progress?.fraction ?? 0) - 11.0 / 12.0) < 1e-9)
    // More steps than the cap clamps the bar at full.
    let over = TaskPanelText.content(rows: [row(1, "p", .running("x"), trail(steps, max: 5))])
    #expect(over?.progress?.fraction == 1)
}

@Test func taskPanelRowChoice() {
    let task = trail([("a", "ok")])
    func pick(_ rows: [PromptRow]) -> Int? {
        TaskPanelText.content(rows: rows).flatMap { c in rows.first { $0.text == c.phrase }?.id }
    }
    let running = row(1, "run", .running("step 1 · a"), task, at: 1)
    let done = row(2, "done", .done("done"), task, at: 1)
    let grammarDone = row(3, "grammar", .done("done"), at: 5)
    // running beats held and listening, even newer ones
    #expect(pick([row(4, "held", .held, at: 9), row(5, "listen", .listening, at: 9), running]) == 1)
    // heard beats an outcome
    #expect(pick([done, row(6, "heard", .heard, at: 0)]) == 6)
    // a task's outcome beats a newer listening and held row
    #expect(pick([done, row(4, "held", .held, at: 9), row(5, "listen", .listening, at: 9)]) == 2)
    // a listening row beats a grammar command's outcome; held comes after listening
    #expect(pick([grammarDone, row(5, "listen", .listening)]) == 5)
    #expect(pick([grammarDone, row(4, "held", .held)]) == 4)
    // stopped beats a newer dropped
    #expect(pick([row(7, "stop", .stopped(""), at: 1), row(8, "drop", .dropped(""), at: 2)]) == 7)
    // with nothing live, the newest outcome wins over an older task's
    #expect(pick([done, grammarDone]) == 3)
    #expect(pick([]) == nil)
}

@Test func taskTrailTransitions() {
    var t = TaskTrail(maxSteps: 3)
    t.begin(number: 1, intent: "a")
    #expect(t.steps == [TaskStepRecord(number: 1, intent: "a", state: .running)])
    t.end(number: 9, failure: nil)
    #expect(t.steps.map(\.state) == [.running])
    t.end(number: 1, failure: nil)
    t.begin(number: 2, intent: "b")
    t.end(number: 2, failure: "boom")
    #expect(t.steps.map(\.state) == [.done, .failed("boom")])

    var board = PromptBoard()
    board.report(id: 1, text: "p", status: .running("step 1"), now: t0)
    board.report(id: 9, trail: t, now: t0)
    #expect(board.rows.count == 1 && board.rows[0].trail == nil)
    board.report(id: 1, trail: t, now: t0)
    board.report(id: 1, text: "p", status: .running("step 2"), now: t0)
    #expect(board.rows[0].trail == t)
    board.report(id: 1, text: "p", status: .done("done"), now: t0)
    board.report(id: 1, trail: TaskTrail(maxSteps: 1), now: t0.advanced(by: .seconds(1)))
    #expect(board.rows[0].trail == t)
    #expect(board.rows[0].updatedAt == t0)
}
