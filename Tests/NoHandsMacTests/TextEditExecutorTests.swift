import Testing
import Foundation
import os
import NoHandsCore
@testable import NoHandsMac

private let doc = "Meeting at noon. Another meeting later."   // "Meeting" at 0, "meeting" at 25, 39 long

private func field(_ caret: Int = 39, length: Int = 0, line: TextSpan? = nil, settable: Bool = true) -> FocusedText {
    FocusedText(value: doc, selection: TextSpan(location: caret, length: length), line: line, rangeSettable: settable)
}

@MainActor @Test func textEditsSelectByAccessibilityThenTypeOrDelete() async {
    // (edit, caret, expected selection, expected input after it)
    let table: [(TextEdit, Int, TextSpan, [String])] = [
        (.replace("meeting", with: "call"), 39, TextSpan(location: 25, length: 7), ["type:call"]),           // nearest before the caret
        (.replace("meeting", with: "call"), 10, TextSpan(location: 0, length: 7), ["type:Call"]),            // none before: the next; copies the capital
        (.replace("the meeting", with: "call"), 39, TextSpan(location: 25, length: 7), ["type:call"]),       // a leading "the" is optional
        (.deletePhrase("another meeting"), 39, TextSpan(location: 17, length: 16), ["press"]),              // takes one adjacent space
        (.selectPhrase("noon"), 0, TextSpan(location: 11, length: 4), []),
        (.caretAfter("noon"), 0, TextSpan(location: 15, length: 0), []),
        (.select(.sentence, last: true), 39, TextSpan(location: 17, length: 22), []),
        (.delete(.word, last: true), 39, TextSpan(location: 32, length: 6), ["press"]),                      // "later" has no space after (a period): the one before goes
        (.changeCase(.upper), 39, TextSpan(location: 33, length: 5), ["type:LATER"]),
    ]
    for (edit, caret, selection, input) in table {
        let (ex, i, ax, _) = make()
        ax.textFocused = true; ax.field = field(caret)
        #expect(await ex.execute([.editText(edit, otherwise: nil)]) == nil, "\(edit)")
        #expect(ax.selections == [selection], "\(edit)")
        #expect(i.calls == input, "\(edit)")
    }
}

@MainActor @Test func textEditsFallBackToKeysOrFailWithTheNextStep() async {
    let unreadable = ActionExecutor.unreadableField
    let line = [KeyChord(.left, [.command]), KeyChord(.right, [.command, .shift])]
    let word = [KeyChord(.left, [.option]), KeyChord(.right, [.option, .shift])]
    let del = KeyChord(.delete)
    // (edit, field, selection takes, expected failure, expected chords)
    let table: [(TextEdit, FocusedText?, Bool, String?, [KeyChord])] = [
        (.select(.line, last: false), nil, true, nil, line),                       // unreadable field
        (.select(.line, last: false), field(), false, nil, line),                 // the range did not take
        (.select(.word, last: false), field(settable: false), true, nil, word),   // not settable
        (.delete(.word, last: false), nil, true, nil, word + [del]),
        (.select(.sentence, last: false), nil, true, unreadable, []),
        (.replace("meeting", with: "call"), nil, true, unreadable, []),
        (.changeCase(.upper), field(), false, unreadable, []),
        (.caretBefore("noon"), field(), false, unreadable, []),
    ]
    for (edit, text, takes, failure, chords) in table {
        let (ex, i, ax, _) = make()
        ax.textFocused = true; ax.field = text; ax.selectionTakes = takes
        #expect(await ex.execute([.editText(edit, otherwise: nil)]) == failure, "\(edit)")
        #expect(i.chords == chords && !i.calls.contains(where: { $0.hasPrefix("type:") }), "\(edit)")
    }
}

@MainActor @Test func caretMovesAreKeysAndNeedNoRead() async {
    let table: [(CaretPlace, KeyChord)] = [
        (.lineStart, KeyChord(.left, [.command])), (.lineEnd, KeyChord(.right, [.command])),
        (.documentStart, KeyChord(.up, [.command])), (.documentEnd, KeyChord(.down, [.command])),
    ]
    for (place, chord) in table {
        let (ex, i, ax, _) = make()
        ax.textFocused = true
        #expect(await ex.execute([.editText(.caret(place), otherwise: nil)]) == nil)
        #expect(i.chords == [chord] && ax.selections.isEmpty)
    }
}

@MainActor @Test func aPhraseThatIsNotThereTypesDictationOrNamesTheSpeakersWords() async {
    // Dictation: the words go in as typing, and the executor says so (the dictation record stays right).
    let (ex, i, ax, _) = make()
    ax.textFocused = true; ax.field = field()
    let edit = TextEdit.deletePhrase("the old files")
    #expect(await ex.execute([.editText(edit, otherwise: "Delete the old files.")]) == nil)
    #expect(i.calls == ["type:Delete the old files."] && ax.selections.isEmpty && ex.editTypedOtherwise)
    // Command mode: a message with the speaker's words, never the field's.
    let (ex2, i2, ax2, _) = make()
    ax2.textFocused = true; ax2.field = field()
    #expect(await ex2.execute([.editText(.replace("lunch", with: "dinner"), otherwise: nil)]) == "no \"lunch\" in the text")
    #expect(i2.calls.isEmpty && !ex2.editTypedOtherwise)
    // Found: the edit runs and the words are not typed.
    #expect(await ex.execute([.editText(.deletePhrase("noon"), otherwise: "Delete noon.")]) == nil)
    #expect(!ex.editTypedOtherwise && ax.selections.count == 1)
}

@MainActor @Test func noTextFieldFailsWithNothingTyped() async {
    for edit in [TextEdit.select(.word, last: false), .caret(.lineEnd), .replace("a", with: "b"), .changeCase(.lower)] {
        let (ex, i, ax, _) = make()
        ax.textFocused = false; ax.field = field()
        #expect(await ex.execute([.editText(edit, otherwise: "words")]) == ActionExecutor.noTextField, "\(edit)")
        #expect(i.calls.isEmpty && ax.selections.isEmpty, "\(edit)")
    }
}

@MainActor @Test func aSpokenStopDuringTheFieldReadKeepsTheEditFromActing() async {
    let (ex, i, ax, _) = make()
    ax.textFocused = true; ax.field = field()
    let reading = OSAllocatedUnfairLock(initialState: false)
    ax.onFieldRead = { reading.withLock { $0 = true }; Thread.sleep(forTimeInterval: 0.2) }
    let task = Task { @MainActor in await ex.execute([.editText(.deletePhrase("noon"), otherwise: nil)]) }
    for _ in 0..<200 where !reading.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
    task.cancel()
    #expect(await task.value == ActionExecutor.cancelled)
    #expect(ax.selections.isEmpty && i.calls.isEmpty)
}

@Test func theFrontAppIsAskedAboutTheFieldOnlyWhenItChangesTheParse() {
    let g = CommandGrammar()
    final class Counter: @unchecked Sendable { var asked = 0 }
    let c = Counter()
    func parsed(_ phrase: String, focused: Bool) -> [Action]? {
        VoicePipeline.parsed(phrase, grammar: g, frontmost: nil) { c.asked += 1; return focused }
    }
    #expect(parsed("go back", focused: true) != nil && c.asked == 0)
    #expect(parsed("select the last sentence", focused: false) != nil && c.asked == 0)   // parses either way
    #expect(parsed("select the second option", focused: false) == nil && c.asked == 1)
    #expect(parsed("select the second option", focused: true) == [.editText(.selectPhrase("the second option"), otherwise: nil)])
}
