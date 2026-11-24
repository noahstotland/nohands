import Testing
import Foundation
@testable import NoHandsCore

private let t0 = ContinuousClock.now

@Test func statusTextToneAndFinality() {
    let cases: [(PromptStatus, String, PromptStatus.Tone, Bool)] = [
        (.listening, "listening…", .active, false),
        (.heard, "heard", .active, false),
        (.running("step 2 · open the menu"), "step 2 · open the menu", .active, false),
        (.held, "held · runs after this task (say stop to cancel)", .waiting, false),
        (.done(""), "done", .good, true),
        (.done("done · open it (2 steps)"), "done · open it (2 steps)", .good, true),
        (.failed("no label 3"), "no label 3", .bad, true),
        (.stopped(""), "stopped", .muted, true),
        (.dropped("skipped (busy)"), "skipped (busy)", .bad, true),
        (.ignored(""), "ignored", .muted, true),
    ]
    for (status, text, tone, final) in cases {
        #expect(status.text == text, "\(status)")
        #expect(status.tone == tone, "\(status)")
        #expect(status.isFinal == final, "\(status)")
    }
}

@Test func reportAddsThenUpdatesOneRowPerPrompt() {
    var b = PromptBoard()
    b.report(id: 1, text: "search for cats", status: .heard, now: t0)
    b.report(id: 1, text: "search for cats", status: .running("step 1 · open youtube"), now: t0.advanced(by: .seconds(1)))
    b.report(id: 2, text: "scroll down", status: .held, now: t0.advanced(by: .seconds(1)))
    #expect(b.rows.map(\.id) == [1, 2])
    #expect(b.rows[0].status == .running("step 1 · open youtube"))
    #expect(b.rows[1].status == .held)
}

@Test func finalRowIsNeverReopened() {
    // A late step line after the task was stopped must not revive the row.
    var b = PromptBoard()
    b.report(id: 1, text: "x", status: .stopped(""), now: t0)
    b.report(id: 1, text: "x", status: .running("step 2 · late"), now: t0)
    #expect(b.rows[0].status == .stopped(""))
    b.report(id: 1, text: "x", status: .done(""), now: t0)   // a later final status still lands
    #expect(b.rows[0].status == .done(""))
}

@Test func overflowDropsTheOldestFinishedRowFirst() {
    var b = PromptBoard()
    b.maxRows = 3
    b.report(id: 1, text: "a", status: .running(""), now: t0)
    b.report(id: 2, text: "b", status: .done(""), now: t0)
    b.report(id: 3, text: "c", status: .held, now: t0)
    b.report(id: 4, text: "d", status: .heard, now: t0)
    #expect(b.rows.map(\.id) == [1, 3, 4])   // the finished one went, not the oldest live one
    b.report(id: 5, text: "e", status: .heard, now: t0)
    #expect(b.rows.map(\.id) == [3, 4, 5])   // nothing finished: the oldest goes
}

@Test func rowsAndNoticesExpire() {
    var b = PromptBoard()
    b.report(id: 1, text: "a", status: .done(""), now: t0)
    b.report(id: 2, text: "b", status: .listening, now: t0)
    b.report(id: 3, text: "c", status: .running(""), now: t0)
    b.notice("loading…", for: .seconds(3), now: t0)
    #expect(b.visibleRows(now: t0).count == 3 && b.visibleNotice(now: t0) != nil)
    #expect(b.nextChange(now: t0) == t0.advanced(by: .milliseconds(1500)))  // the finished row goes first
    let later = t0.advanced(by: .seconds(4))
    #expect(b.visibleNotice(now: later) == nil)
    #expect(b.visibleRows(now: later).map(\.id) == [2, 3])                  // the finished row left after 1.5 s
    #expect(b.nextChange(now: later) == t0.advanced(by: b.listeningLinger))
    b.prune(now: t0.advanced(by: .seconds(11)))
    #expect(b.rows.map(\.id) == [3])                                        // listening words that never arrived
    #expect(b.nextChange(now: t0.advanced(by: .seconds(11))) == t0.advanced(by: b.activeLinger))
}
