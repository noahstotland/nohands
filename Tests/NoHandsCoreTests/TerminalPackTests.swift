import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let term = "com.apple.Terminal"
private let packOnly: [(String, [Action])] = [
    ("new window", chord(.n)), ("open a new terminal window", chord(.n)), ("clear", chord(.k)),
    ("clear screen", chord(.l, [.command, .control])), ("clear history", chord(.k, [.command, .option])),
    ("scroll to top", chord(.home)), ("scroll to the bottom", chord(.end)), ("split the window", chord(.d)),
    ("close the split pane", chord(.d, [.command, .shift])), ("make the text bigger", chord(.equal, [.command, .shift])),
    ("smaller font", chord(.minus)), ("reset font size", chord(.zero)),
    ("interrupt", chord(.c, [.control])), ("cancel command", chord(.c, [.control])),
]

@Test func terminalPhrasesRunOnlyInTerminal() {
    let grammar = CommandGrammar()
    let globals: [(String, [Action])] = [
        ("new tab", chord(.t)), ("close tab", chord(.w)), ("close window", chord(.w, [.command, .shift])),
        ("next tab", chord(.tab, [.control])), ("previous tab", chord(.tab, [.control, .shift])),
        ("find", chord(.f)), ("page up", chord(.pageUp, [])), ("page down", chord(.pageDown, [])),
    ]
    for (phrase, expected) in packOnly + globals {
        #expect(grammar.parse(phrase, frontmost: term) == expected, Comment(rawValue: phrase))
    }
    for (phrase, expected) in packOnly {
        for app in ["com.apple.mail", nil] { #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase)) }
    }
}

@Test func terminalHasNoStopPhrase() {
    for phrase in AppPack.terminal.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
    let grammar = CommandGrammar()
    for phrase in ["stop", "cancel", "cancel that"] {
        #expect(grammar.parse(phrase, frontmost: term) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
}
