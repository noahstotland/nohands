import Testing
@testable import NoHandsCore

@Test func attentionGateChecksTheStartOfTheTranscript() {
    let g = AttentionGate(configured: "Computer")
    let table: [(String, AttentionGate.Result)] = [
        ("computer go back", .addressed("go back")),
        ("Computer, go back.", .addressed("go back.")),
        ("computer", .wordOnly),
        ("Computer.", .wordOnly),
        ("computer, ...", .wordOnly),
        ("tell the computer to go back", .notAddressed),
        ("go back", .notAddressed),
        ("um, computer, go back", .addressed("go back")),
        ("hey computer click Save", .addressed("click Save")),
        ("so um computer go back", .notAddressed),
        ("computers go back", .notAddressed),
        ("computer's back", .notAddressed),
        ("", .notAddressed),
    ]
    for (transcript, expected) in table {
        #expect(g.check(transcript) == expected, "\(transcript)")
    }
    #expect(AttentionGate.off.check("computer go back") == .off)
    #expect(AttentionGate(configured: "hey mac").check("Hey Mac, new tab") == .addressed("new tab"))
    #expect(AttentionGate(configured: "hey mac").check("hey computer new tab") == .notAddressed)
}

@Test func attentionGateStopsWithOrWithoutTheWord() {
    let on = AttentionGate(configured: "computer")
    for gate in [on, .off] {
        for stop in ["stop", "Stop, stop!", "never mind"] { #expect(gate.isStop(stop), "\(stop)") }
        #expect(!gate.isStop("computer stop dictating"))
        #expect(!gate.isStop("go back"))
    }
    for stop in ["computer stop", "Computer, never mind", "um computer cancel that"] { #expect(on.isStop(stop), "\(stop)") }
    #expect(!AttentionGate.off.isStop("computer stop"))
}

@Test func attentionGateConfiguredValueIsNormalizedOrOff() {
    #expect(AttentionGate(configured: "  Hey,  Mac! ").words == ["hey", "mac"])
    for unusable in ["", "  ", "?!", "stop", "never mind", "one two three four"] {
        #expect(!AttentionGate(configured: unusable).isOn, "\(unusable)")
    }
}
