import Testing
@testable import NoHandsCore

@Test func spokenPunctuation() {
    #expect(DictationFormatter.format("hello world period this is a test exclamation mark") == "Hello world. This is a test!")
    #expect(DictationFormatter.format("yes comma please question mark") == "Yes, please?")
    #expect(DictationFormatter.format("one colon two semicolon three") == "One: two; three")
    #expect(DictationFormatter.format("open quote hi close quote") == "\"hi\"")
    #expect(DictationFormatter.format("open paren note close paren") == "(note)")
    #expect(DictationFormatter.format("a dash b") == "A - b")
    #expect(DictationFormatter.format("well hyphen known") == "Well-known")
}

@Test func newlines() {
    #expect(DictationFormatter.format("first line new line second line") == "First line\nSecond line")
    #expect(DictationFormatter.format("para one new paragraph para two") == "Para one\n\nPara two")
}

@Test func preservesAsrPunctuationAndCasing() {
    #expect(DictationFormatter.format("Hello, I'm Noah. Nice to meet you.") == "Hello, I'm Noah. Nice to meet you.")
    #expect(DictationFormatter.format("send it to NASA period") == "Send it to NASA.")
}

@Test func capitalizeStartFalse() {
    #expect(DictationFormatter.format("world period", capitalizeStart: false) == "world.")
}

@Test func sessionSpacing() {
    var s = DictationSession()
    #expect(s.next("hello") == "Hello")
    #expect(s.next("world period") == " world.")
    #expect(s.next("next sentence") == " Next sentence")
    #expect(s.next("new line") == "\n")
    #expect(s.next("after break") == "After break")
}

@Test func grammarTypeUsesFormatter() {
    #expect(CommandGrammar().parse("type hello comma world") == [.typeText("Hello, world")])
}

@Test func noDoubledPunctuation() {
    #expect(DictationFormatter.format("hello, comma there") == "Hello, there")
    #expect(DictationFormatter.format("Hello world. Period") == "Hello world.")
}
