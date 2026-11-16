import Testing
import Foundation
import os
import NoHandsCore
@testable import NoHandsMac

private let doc = "Hello there. How are you doing today?"   // the first sentence ends at 12, the second at 37

private func field(_ caret: Int = 37, length: Int = 0, value: String = doc, settable: Bool = true) -> FocusedText {
    FocusedText(value: value, selection: TextSpan(location: caret, length: length), line: nil, rangeSettable: settable)
}

@MainActor private func rewriteRig(_ field: FocusedText?, focused: Bool = true, _ rewriter: FakeRewriter?,
                                   ax: FakeElements = FakeElements()) -> (ActionExecutor, FakeInput, FakeElements) {
    let input = FakeInput()
    let ex = ActionExecutor(input: input, ax: ax, overlay: FakeOverlay(), config: AppConfig(), frontTimeout: .milliseconds(150))
    ax.fieldFocused = focused; ax.field = field
    ex.rewriter = rewriter
    return (ex, input, ax)
}

private let shorter = Action.rewriteText(.style(.shorter))

@MainActor @Test func aRewriteReplacesTheSubjectOnceWithTheCleanedAnswer() async {
    // (field, answer, subject sent, selection set, typed or nothing, report counts)
    let table: [(FocusedText, String, String, TextSpan?, String?, Int)] = [
        (field(37), "  How are you?\n", "How are you doing today?", TextSpan(location: 13, length: 24), "How are you?", 12),   // last sentence; the line break and edges follow the source
        (field(6, length: 5), "here", "there", TextSpan(location: 6, length: 5), "here", 4),                                // a selection wins
        (field(12), "Hi", "Hello there.", TextSpan(location: 0, length: 12), "Hi", 2),
        (field(37), "How are you doing today?", "How are you doing today?", nil, nil, 24),                                  // unchanged: nothing typed
    ]
    for (text, answer, subject, selection, typed, count) in table {
        let rewriter = FakeRewriter(.success(answer))
        let (ex, i, ax) = rewriteRig(text, rewriter)
        #expect(await ex.execute([.rewriteText(.translate(language: "French"))]) == nil, "\(subject)")
        #expect(rewriter.calls.map(\.text) == [subject] && rewriter.calls.first?.how == .translate(language: "French"), "\(subject)")
        #expect(ax.selections == (selection.map { [$0] } ?? []) && i.calls == (typed.map { ["type:\($0)"] } ?? []), "\(subject)")
        #expect(ex.takeRewrite()?.to == count, "\(subject)")
        #expect(ex.takeRewrite() == nil)
    }
}

@MainActor @Test func aMultiLineAnswerIsTypedWithShiftReturnAndNeverTextWithBreaksOrTabs() async {
    let value = "Line one\nline two"
    let rewriter = FakeRewriter(.success("One\t1\n\nTwo\r\nThree\u{2028}\tFour"))
    let (ex, i, _) = rewriteRig(field(0, length: value.count, value: value), rewriter)
    #expect(await ex.execute([shorter]) == nil)
    #expect(i.calls == ["type:One 1", "press", "press", "type:Two", "press", "type:Three", "press", "type: Four"])
    #expect(i.chords == Array(repeating: KeyChord(.return, [.shift]), count: 4))
    #expect(!i.calls.contains { $0.hasPrefix("type:") && ($0.contains("\n") || $0.contains("\t")) })
}

@MainActor @Test func aRewriteThatCannotRunFailsWithTheNextStepAndSendsNothing() async {
    let cantRead = ActionExecutor.rewriteUnreadable
    let ok = FakeRewriter(.success("x"))
    // (field, focused, rewriter, selection takes, expected failure, rewriter asked)
    let table: [(FocusedText?, Bool, FakeRewriter?, Bool, String, Bool)] = [
        (field(), true, nil, true, ActionExecutor.rewriteNeedsModel, false),
        (field(), false, ok, true, ActionExecutor.noTextField, false),
        (nil, true, ok, true, cantRead, false), (field(settable: false), true, ok, true, cantRead, false),
        (field(0, value: ""), true, ok, true, RewriteError.nothingToRewrite.message, false),
        (field(5), true, ok, true, RewriteError.nothingToRewrite.message, false),
        (field(0, length: 2001, value: String(repeating: "a", count: 2001)), true, ok, true, RewriteError.subjectTooLong.message, false),
        (field(), true, FakeRewriter(.failure(IntentError.timeout)), true, "timed out", true),
        (field(), true, FakeRewriter(.failure(IntentError.localUnavailable)), true, PipelineText.localNotRunning, true),
        (field(), true, FakeRewriter(.failure(RewriteError.noAnswer)), true, RewriteError.noAnswer.message, true),
        (field(), true, FakeRewriter(.success(" \n ")), true, RewriteError.noAnswer.message, true),
        (field(), true, FakeRewriter(.success(String(repeating: "a", count: 2001))), true, RewriteError.answerTooLong.message, true),
        (field(), true, FakeRewriter(.success("Fine.")), false, cantRead, true),   // the field would not take the selection
    ]
    for (text, focused, rewriter, takes, failure, asked) in table {
        let (ex, i, ax) = rewriteRig(text, focused: focused, rewriter)
        ax.selectionTakes = takes
        #expect(await ex.execute([shorter]) == failure, "\(failure)")
        #expect((rewriter?.calls.count ?? 0) == (asked ? 1 : 0) && i.calls.isEmpty, "\(failure)")
    }
    // Turned off by the user: the text says which switch.
    let (ex, _, _) = rewriteRig(field(), nil)
    var off = AppConfig(); off.intentBackend = .off
    ex.useRewriter(config: off)
    #expect(await ex.execute([shorter]) == ActionExecutor.rewriteOff)
}

@MainActor @Test func aFieldChangedDuringTheWaitTypesNothing() async {
    // What the user did meanwhile.
    let changes: [(String, @Sendable (FakeElements) -> Void)] = [
        ("typed", { $0.field = field(value: doc + " Fine.") }),
        ("moved the caret", { $0.field = field(5) }),
        ("left the field", { $0.fieldFocused = false }),
    ]
    for (name, change) in changes {
        let ax = FakeElements()
        let (ex, i, _) = rewriteRig(field(), FakeRewriter(.success("Fine."), during: { change(ax) }), ax: ax)
        #expect(await ex.execute([shorter]) == ActionExecutor.rewriteChanged, "\(name)")
        #expect(ax.selections.isEmpty && i.calls.isEmpty, "\(name)")
    }
}

@MainActor @Test func aSpokenStopDuringTheWaitTypesNothing() async {
    let (ex, i, ax) = rewriteRig(field(), nil)
    let waiting = OSAllocatedUnfairLock(initialState: false)
    ex.rewriter = FakeRewriter(.success("Fine.")) {
        waiting.withLock { $0 = true }
        for _ in 0..<300 where !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
    }
    let task = Task { @MainActor in await ex.execute([shorter]) }
    for _ in 0..<300 where !waiting.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
    task.cancel()
    #expect(await task.value == ActionExecutor.cancelled)
    #expect(ax.selections.isEmpty && i.calls.isEmpty && ex.takeRewrite() == nil)
}
