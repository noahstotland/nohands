import Testing
@testable import NoHandsCore

private func spelled(_ phrase: String) -> Result<String, SpellError> {
    Speller.spell(CommandGrammar.normalize(phrase))
}

@Test func spellerTypesEachTokenKind() {
    let cases: [(String, String)] = [
        ("a b c", "abc"), ("bee see you why are oh", "bcuyro"), ("double you", "w"),
        ("alpha bravo x-ray xray", "abxx"), ("x ray", "x"), ("kilo x ray yankee", "kxy"),
        ("one two nine zero", "1290"), ("42 7", "427"),
        ("capital kilo nine x ray", "K9x"), ("capital a capital bee", "AB"),
        ("a dash b dot c underscore d space e at sign f", "a-b.c_d e@f"),
    ]
    for (phrase, expected) in cases {
        #expect(spelled(phrase) == .success(expected), "\(phrase)")
    }
}

@Test func spellerFailsWholePhraseOnABadToken() {
    let cases: [(String, SpellError)] = [
        ("kilo banana nine", .unknown("banana")), ("alpha to", .unknown("to")), ("at", .unknown("at")),
        ("ray", .unknown("ray")), ("capital nine", .capitalWithoutLetter),
        ("capital capital a", .capitalWithoutLetter), ("a capital", .capitalWithoutLetter), ("", .empty),
    ]
    for (phrase, expected) in cases {
        #expect(spelled(phrase) == .failure(expected), "\(phrase)")
    }
}

@Test func spellPhraseIsTypedOrRejectedNeverGuessed() {
    let g = CommandGrammar()
    #expect(g.parse("Spell capital kilo nine x ray.") == [.typeText("K9x")])
    #expect(g.rejection("spell capital kilo nine x ray") == nil)
    #expect(g.parse("spell kilo banana") == nil)
    #expect(g.rejection("spell kilo banana") == "can't spell \"banana\": say spell again")
    #expect(g.rejection("spell") != nil)
    #expect(g.rejection("type kilo banana") == nil)
    var m = ModeMachine()
    #expect(m.route("spell kilo banana") == .reject("can't spell \"banana\": say spell again"))
    _ = m.route("start dictating")
    #expect(m.route("spell kilo banana") == .execute([.typeText("Spell kilo banana")]))
}
