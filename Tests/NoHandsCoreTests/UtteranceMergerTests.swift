import Testing
@testable import NoHandsCore

@Test func unfinishedTranscriptsAreDetected() {
    #expect(UtteranceMerger.isUnfinished("click the"))
    #expect(UtteranceMerger.isUnfinished("Open"))
    #expect(UtteranceMerger.isUnfinished("scroll down and"))
    #expect(UtteranceMerger.isUnfinished("um"))
    #expect(UtteranceMerger.isUnfinished("Spell capital kilo nine"))   // spelling pauses: held for the longer window
    #expect(!UtteranceMerger.isUnfinished("click the back button"))
    #expect(!UtteranceMerger.isUnfinished("go back"))
    #expect(!UtteranceMerger.isUnfinished(""))
}

@Test func holdDependsOnCompletenessAndDangling() {
    let m = UtteranceMerger(windowMs: 500, unfinishedWindowMs: 1500)
    #expect(m.hold(for: "go back", isComplete: true) == .zero)
    #expect(m.hold(for: "open the thing", isComplete: false) == .milliseconds(500))
    #expect(m.hold(for: "click the", isComplete: false) == .milliseconds(1500))
    #expect(m.hold(for: "scroll to", isComplete: true) == .milliseconds(1500))   // dangling beats grammar
}

@Test func mergeJoinsWithOneSpace() {
    #expect(UtteranceMerger.merge("click the ", " back button") == "click the back button")
    #expect(UtteranceMerger.merge("", "x") == "x")
    #expect(UtteranceMerger.merge("x", "  ") == "x")
}

@Test func orderedSchemaPutsIntentBeforeActions() throws {
    let s = IntentSchema.orderedSchema.serialized
    let i = try #require(s.range(of: "\"intent\""))
    let a = try #require(s.range(of: "\"actions\""))
    #expect(i.lowerBound < a.lowerBound)
    #expect(s.contains(#""required":["intent","status","actions"]"#))
    #expect(OrderedJSON.string("a\"b\n").serialized == #""a\"b\n""#)
}

@Test func decoderIgnoresIntentField() throws {
    let a = try IntentDecoder.actions(fromPayloadText: #"{"intent":"Go back.","actions":[{"kind":"press_key","key":"left","modifiers":["command"]}]}"#)
    #expect(a.count == 1)
}
