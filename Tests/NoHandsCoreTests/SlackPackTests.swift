import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let leadPack = AppPack(name: "Lead", bundleIDs: ["lead"], phrases: [:], typingLeads: ["jump to": [.pressKey(KeyChord(.k, [.command])), .wait(ms: 300)]])
private let open: [Action] = [.pressKey(KeyChord(.k, [.command])), .wait(ms: 300)]

@Test func typingLeadTypesTheRestInTheSpeakersWords() {
    let grammar = CommandGrammar(packs: [leadPack])
    let cases: [(String, String?, [Action]?)] = [
        ("jump to general", "lead", open + [.typeText("general")]),
        ("Jump to the Design Team channel.", "lead", open + [.typeText("Design Team")]),
        ("jump to", "lead", open),
        ("jump to the", "lead", open),
        ("jump to general", "com.apple.Safari", nil),
        ("jump to general", nil, nil),
        ("stop", "lead", grammar.parse("stop")),
    ]
    for (phrase, app, expected) in cases { #expect(grammar.parse(phrase, frontmost: app) == expected, Comment(rawValue: phrase)) }
}
