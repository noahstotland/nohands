import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let safari = "com.apple.Safari"
private let packOnly: [(String, [Action])] = [
    ("new safari window", chord(.n)), ("open a new private window", chord(.n, [.command, .shift])),
    ("reopen closed tab", chord(.t, [.command, .shift])), ("go to the address bar", chord(.l)),
    ("bookmark this page", chord(.d)), ("show bookmarks sidebar", chord(.one, [.command, .control])),
    ("edit bookmarks", chord(.b, [.command, .option])), ("read later", chord(.d, [.command, .shift])),
    ("hide reading list", chord(.two, [.command, .control])), ("go to history", chord(.y)),
    ("open downloads", chord(.l, [.command, .option])), ("show tab overview", chord(.backslash, [.command, .shift])),
    ("toggle sidebar", chord(.l, [.command, .shift])), ("reader mode", chord(.r, [.command, .shift])),
    ("favorites bar", chord(.b, [.command, .shift])), ("hard reload", chord(.r, [.command, .option])),
    ("view source", chord(.u, [.command, .option])), ("print this page", chord(.p)),
    ("safari home page", chord(.h, [.command, .shift])),
    ("move tab to new window", [.menuItem("Move Tab to New Window")]), ("merge windows", [.menuItem("Merge All Windows")]),
]

@Test func safariPhrasesRunOnlyInSafari() {
    let grammar = CommandGrammar()
    for (phrase, expected) in packOnly { #expect(grammar.parse(phrase, frontmost: safari) == expected, Comment(rawValue: phrase)) }
    for (phrase, expected) in packOnly {
        for app in ["com.apple.mail", nil] { #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase)) }
    }
}

@Test func safariKeepsGlobalsAndNeverStops() {
    let grammar = CommandGrammar()
    for phrase in ["new tab", "close tab", "close window", "next tab", "previous tab", "reload", "go back", "go forward", "find",
                   "zoom in", "zoom out", "actual size", "home", "tab 3", "last tab", "close other tabs", "go to youtube",
                   "stop", "cancel"] {
        #expect(grammar.parse(phrase, frontmost: safari) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    for phrase in AppPack.safari.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
}
