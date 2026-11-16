import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let mail = "com.apple.mail"
private let packOnly: [(String, [Action])] = [
    ("open a new message", chord(.n)), ("compose email", chord(.n)), ("reply", chord(.r)),
    ("reply to all", chord(.r, [.command, .shift])), ("forward the message", chord(.f, [.command, .shift])),
    ("send the email", chord(.d, [.command, .shift])), ("undo send", chord(.z)), ("next message", chord(.down, [])),
    ("last message", chord(.up, [])), ("check mail", chord(.n, [.command, .shift])),
    ("mark unread", chord(.u, [.command, .shift])), ("unflag", chord(.l, [.command, .shift])),
    ("archive it", chord(.a, [.command, .control])), ("junk", chord(.j, [.command, .shift])),
    ("delete this message", chord(.delete)), ("hide mailbox list", chord(.m, [.command, .shift])),
    ("go to the inbox", chord(.one)), ("go to sent", [.menuItem("Mailbox > Go to Favorite Mailbox > Sent")]),
    ("search mail", chord(.f, [.command, .option])), ("attach a file", chord(.a, [.command, .shift])),
    ("close this message", chord(.w)),
]

@Test func mailPhrasesRunOnlyInMail() {
    let grammar = CommandGrammar()
    for (phrase, expected) in packOnly { #expect(grammar.parse(phrase, frontmost: mail) == expected, Comment(rawValue: phrase)) }
    for (phrase, expected) in packOnly {
        for app in ["com.apple.Safari", nil] { #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase)) }
    }
}

@Test func mailKeepsGlobalsAndNeverStops() {
    let grammar = CommandGrammar()
    for phrase in ["delete", "up", "down", "undo", "find", "close window", "stop", "cancel", "cancel that"] {
        #expect(grammar.parse(phrase, frontmost: mail) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    for phrase in AppPack.mail.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
}
