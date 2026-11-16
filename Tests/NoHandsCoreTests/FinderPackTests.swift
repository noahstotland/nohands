import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let finder = "com.apple.finder"
private let packOnly: [(String, [Action])] = [
    ("new finder window", chord(.n)), ("open a new folder", chord(.n, [.command, .shift])),
    ("close the window", [.menuItem("File > Close Window")]), ("go to the downloads folder", chord(.l, [.command, .option])),
    ("go to my documents", chord(.o, [.command, .shift])), ("go home", chord(.h, [.command, .shift])),
    ("go to icloud drive", chord(.i, [.command, .shift])), ("go to folder", chord(.g, [.command, .shift])),
    ("go up a folder", chord(.up)), ("list view", chord(.two)), ("view as columns", chord(.three)),
    ("hide sidebar", chord(.s, [.command, .control])), ("show path bar", chord(.p, [.command, .option])),
    ("get info", chord(.i)), ("open it", chord(.o)), ("quick look", chord(.space, [])), ("duplicate this", chord(.d)),
    ("make an alias", [.menuItem("File > Make Alias")]), ("rename", chord(.return, [])),
    ("paste here as a move", chord(.v, [.command, .option])), ("trash this file", chord(.delete)),
    ("put it back", [.menuItem("File > Put Back")]), ("show hidden files", chord(.period, [.command, .shift])),
    ("search files", chord(.f)),
]

@Test func finderPhrasesRunOnlyInFinder() {
    let grammar = CommandGrammar()
    for (phrase, expected) in packOnly { #expect(grammar.parse(phrase, frontmost: finder) == expected, Comment(rawValue: phrase)) }
    for (phrase, expected) in packOnly {
        for app in ["com.apple.Safari", nil] { #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase)) }
    }
}

@Test func finderKeepsOpenFilesGlobalsAndNeverTrashesOnOneWord() {
    let grammar = CommandGrammar()
    for phrase in ["open the downloads folder", "open my documents folder", "open trash", "open file budget",
                   "open the reports folder", "open my last keynote", "open downloads", "open home", "empty trash",
                   "show desktop", "home", "delete", "up", "copy", "paste", "select all", "undo", "find", "go back",
                   "new tab", "stop", "cancel"] {
        #expect(grammar.parse(phrase, frontmost: finder) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    for phrase in ["trash", "go to trash"] { #expect(grammar.parse(phrase, frontmost: finder) != chord(.delete), Comment(rawValue: phrase)) }
    for phrase in AppPack.finder.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
}
