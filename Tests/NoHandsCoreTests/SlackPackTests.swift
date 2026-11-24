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
    ]
    for (phrase, app, expected) in cases { #expect(grammar.parse(phrase, frontmost: app) == expected, Comment(rawValue: phrase)) }
}

private let slack = "com.tinyspeck.slackmacgap"
private let packOnly: [(String, [Action])] = [
    ("quick switcher", chord(.k)), ("compose", chord(.n)), ("dms", chord(.k, [.command, .shift])),
    ("show threads", chord(.t, [.command, .shift])), ("mentions", chord(.m, [.command, .shift])),
    ("saved items", chord(.s, [.command, .shift])), ("search slack", chord(.g)), ("search this channel", chord(.f)),
    ("previous channel", chord(.up, [.option])), ("channel down", chord(.down, [.option])),
    ("previous unread", chord(.up, [.option, .shift])), ("next unread channel", chord(.down, [.option, .shift])),
    ("unreads", chord(.a, [.command, .shift])), ("mark all read", chord(.escape, [.shift])),
    ("mark as read", chord(.escape, [])), ("attach a file", chord(.o)), ("hide sidebar", chord(.d, [.command, .shift])),
    ("leave huddle", chord(.h, [.command, .shift])),
    ("close thread", chord(.period)), ("browse channels", chord(.l, [.command, .shift])),
    ("people", chord(.e, [.command, .shift])), ("home view", chord(.one, [.control])), ("settings", chord(.comma)),
    ("send it", chord(.return, [])),
]

@Test func slackPhrasesRunOnlyInSlack() {
    let grammar = CommandGrammar()
    let globals: [(String, [Action])] = [
        ("close window", chord(.w)), ("go back", chord(.leftBracket)), ("find", chord(.f)),
        ("escape", chord(.escape, [])), ("mute", [.volume(.mute(true))]),
    ]
    for (phrase, expected) in packOnly + globals {
        #expect(grammar.parse(phrase, frontmost: slack) == expected, Comment(rawValue: phrase))
    }
    #expect(grammar.parse("close window", frontmost: nil) == chord(.w, [.command, .shift]))
    for (phrase, expected) in packOnly {
        for app in ["com.apple.Safari", nil] { #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase)) }
    }
}

@Test func slackHasNoStopPhrase() {
    for phrase in AppPack.slack.phrases.keys { #expect(!phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase)) }
    let grammar = CommandGrammar()
    for phrase in ["stop", "cancel", "cancel that", "stop jump to general"] {
        #expect(grammar.parse(phrase, frontmost: slack) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
}
