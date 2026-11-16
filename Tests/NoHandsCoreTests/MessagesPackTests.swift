import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let msgs = "com.apple.MobileSMS"
private let packOnly: [(String, [Action])] = [
    ("new message", chord(.n)), ("open a new message", chord(.n)), ("compose", chord(.n)),
    ("go to the next conversation", chord(.tab, [.control])), ("last conversation", chord(.tab, [.control, .shift])),
    ("search", chord(.f)), ("the details", chord(.i)), ("info", chord(.i)),
    ("mark as unread", [.menuItem("Mark as Unread")]), ("mark read", [.menuItem("Mark as Read")]),
    ("add emoji", chord(.space, [.command, .control])), ("tapback", chord(.t)), ("react", chord(.t)),
    ("delete the conversation", [.menuItem("Delete Conversation…")]),
]

@Test func messagesPhrasesRunOnlyInMessages() {
    let grammar = CommandGrammar()
    let globals: [(String, [Action])] = [
        ("close window", chord(.w)), ("find", chord(.f)), ("next tab", chord(.tab, [.control])),
        ("previous tab", chord(.tab, [.control, .shift])), ("search for mom", [.search("mom")]),
    ]
    for (phrase, expected) in packOnly + globals {
        #expect(grammar.parse(phrase, frontmost: msgs) == expected, Comment(rawValue: phrase))
    }
    for (phrase, expected) in packOnly {
        for app in ["com.apple.Safari", nil] { #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase)) }
    }
    #expect(grammar.parse("close window", frontmost: "com.apple.Safari") == chord(.w, [.command, .shift]))
}

@Test func messagesHasNoStopOrSendPhrase() {
    for phrase in AppPack.messages.phrases.keys {
        let words = phrase.split(separator: " ")
        #expect(!StopWords.isStop(phrase) && !words.contains("stop") && !words.contains("send"), Comment(rawValue: phrase))
    }
    let grammar = CommandGrammar()
    for phrase in ["stop", "cancel", "cancel that"] {
        #expect(grammar.parse(phrase, frontmost: msgs) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
}
