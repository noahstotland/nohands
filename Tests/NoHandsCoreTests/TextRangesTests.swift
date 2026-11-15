import Testing
import Foundation
@testable import NoHandsCore

/// The slice of `text` a range covers, in UTF-16 offsets like Accessibility's.
private func slice(_ text: String, _ r: TextSpan?) -> String? {
    r.map { (text as NSString).substring(with: NSRange(location: $0.location, length: $0.length)) }
}

@Test func unitsAtAndBeforeTheCaret() {
    let text = "Hello there. How are you? I'm fine"
    let emoji = "hi 😀 there. ok"
    let lines = "first line\nsecond line\n\nthird"
    // (text, unit, last, caret, expected slice)
    let table: [(String, TextUnit, Bool, Int, String?)] = [
        (text, .word, false, 0, "Hello"), (text, .word, false, 3, "Hello"), (text, .word, false, 5, "Hello"),
        (text, .word, false, 6, "there"),                                  // the caret touches the start of "there"
        (text, .word, false, 34, "fine"), (text, .word, false, 29, "I'm"),   // apostrophe inside a word
        (text, .word, true, 12, "there"), (text, .word, true, 11, "there"), (text, .word, true, 10, "Hello"), (text, .word, true, 0, nil),
        (text, .sentence, false, 3, "Hello there."), (text, .sentence, false, 13, "How are you?"),
        (text, .sentence, true, 34, "I'm fine"), (text, .sentence, true, 26, "How are you?"), (text, .sentence, true, 12, "Hello there."),
        (text, .sentence, true, 5, nil),
        (emoji, .word, false, 8, "there"), (emoji, .word, true, 8, "hi"), (emoji, .word, false, 4, "hi"),
        (lines, .paragraph, false, 14, "second line"), (lines, .paragraph, true, 30, "third"), (lines, .paragraph, false, 23, "second line"),
        (lines, .line, false, 3, "first line"), (lines, .line, true, 30, "third"),
        ("", .word, false, 0, nil), ("   ", .sentence, false, 1, nil),
    ]
    for (t, unit, last, caret, want) in table {
        #expect(slice(t, TextRanges.unit(unit, last: last, in: t, caret: caret)) == want, "\(unit) last=\(last) caret=\(caret) in \(t.debugDescription)")
    }
    // The field's own (visual) line wins over the paragraph and loses its newline.
    let wrapped = "aaa bbb ccc\nddd"
    #expect(slice(wrapped, TextRanges.unit(.line, last: false, in: wrapped, caret: 9, line: TextSpan(location: 8, length: 4))) == "ccc")
}

@Test func deletionTakesOneAdjacentSpaceOrTheNewline() {
    // (text, unit, selection to delete, text left)
    let table: [(String, TextUnit?, String, String)] = [
        ("a b c", .word, "b", "a c"),                       // the space after
        ("Hello world.", .word, "world", "Hello."),          // none after, the one before
        ("Hello world", nil, "world", "Hello"),
        ("Hi. How are you? Fine.", .sentence, "How are you?", "Hi. Fine."),
        ("One. Two.", .sentence, "Two.", "One."),
        ("a\nb\nc", .line, "b", "a\nc"), ("a\nb\nc", .paragraph, "c", "a\nb"), ("only", .line, "only", ""),
        ("a\r\nb", .paragraph, "a", "b"),
    ]
    for (text, unit, target, left) in table {
        let r = (text as NSString).range(of: target, options: .backwards)
        let d = TextRanges.deletion(of: TextSpan(location: r.location, length: r.length), unit: unit, in: text)
        #expect((text as NSString).replacingCharacters(in: NSRange(location: d.location, length: d.length), with: "") == left, "\(text.debugDescription)")
    }
}

@Test func phraseSearchPicksTheNearestWholeMatch() {
    let text = "Meeting at noon. Another meeting later, then a meeting."
    // (phrase, caret, expected location or nil)
    let table: [(String, Int, Int?)] = [
        ("meeting", 55, 47), ("meeting", 46, 25), ("meeting", 16, 0),   // the nearest match ending at or before the caret
        ("later", 0, 33), ("meeting", 3, 0),                            // none before: the nearest after (a match around the caret counts as after)
        ("MEETING.", 55, 47),                                           // case-insensitive, trailing ASR punctuation dropped
        ("meet", 55, nil), ("eeting", 55, nil), ("meetings", 55, nil),    // whole words only, no fuzzy guess
        ("at  noon", 55, 8), ("another   meeting", 0, 17),              // whitespace runs match any whitespace
        ("", 0, nil), ("...", 0, nil), ("lunch", 55, nil),
    ]
    for (phrase, caret, want) in table {
        #expect(TextRanges.find(phrase, in: text, caret: caret)?.location == want, "\(phrase) @\(caret)")
    }
    #expect(slice("it's Bob's, ok", TextRanges.find("bob's", in: "it's Bob's, ok", caret: 0)) == "Bob's")
    #expect(slice("it’s Bob’s", TextRanges.find("it's", in: "it’s Bob’s", caret: 10)) == "it’s")   // curly apostrophe
    #expect(slice("😀 meeting 😀", TextRanges.find("meeting", in: "😀 meeting 😀", caret: 0)) == "meeting")
    #expect(TextRanges.find("meeting", in: "😀 meeting", caret: 20)?.location == 3)   // UTF-16 offset, past the pair
}

@Test func replacementCopiesALeadingCapital() {
    let table: [(String, String, String)] = [
        ("call", "Meeting", "Call"), ("call", "meeting", "call"), ("Call", "meeting", "Call"),
        ("a new one", "The filter", "A new one"), ("123", "Meeting", "123"), ("", "Meeting", ""),
    ]
    for (b, found, want) in table { #expect(TextRanges.replacement(b, replacing: found) == want, "\(b) over \(found)") }
}

@Test func caseChangesActOnTheSelectionOrTheWordBeforeTheCaret() {
    #expect(TextRanges.changeCase(.capitalize, of: "hello big world") == "Hello Big World")
    #expect(TextRanges.changeCase(.capitalize, of: "don't  go, iPhone") == "Don't  Go, IPhone")
    #expect(TextRanges.changeCase(.upper, of: "Hello") == "HELLO")
    #expect(TextRanges.changeCase(.lower, of: "Hello") == "hello")
    let text = "say hello now"
    #expect(slice(text, TextRanges.caseTarget(in: text, selection: TextSpan(location: 4, length: 5))) == "hello")
    #expect(slice(text, TextRanges.caseTarget(in: text, selection: TextSpan(location: 9, length: 0))) == "hello")
    #expect(slice(text, TextRanges.caseTarget(in: text, selection: TextSpan(location: 10, length: 0))) == "hello")
    #expect(TextRanges.caseTarget(in: text, selection: TextSpan(location: 0, length: 0)) == nil)
}
