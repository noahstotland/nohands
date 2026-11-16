import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let finder = "com.apple.finder"
/// Lead and article forms that reach a key only through `PhraseLead.strip`.
private let leadForms: [(String, [Action])] = [
    ("open a new folder", chord(.n, [.command, .shift])), ("open the new finder window", chord(.n)),
]

@Test func everyFinderPhraseRunsOnlyInFinder() {
    let grammar = CommandGrammar(), bare = CommandGrammar(packs: PackSet([]))
    for (phrase, expected) in AppPack.finder.phrases.map({ ($0.key, $0.value) }) + leadForms {
        #expect(grammar.parse(phrase, frontmost: finder) == expected, Comment(rawValue: phrase))
        for app in ["com.apple.TextEdit", nil] {
            #expect(grammar.parse(phrase, frontmost: app) == bare.parse(phrase, frontmost: app), Comment(rawValue: phrase))
        }
    }
}

@Test func finderKeepsOpenFilesGlobalsAndNeverTrashesOnOneWord() {
    let grammar = CommandGrammar()
    for phrase in ["open the downloads folder", "open my documents folder", "open trash", "open file budget",
                   "open the reports folder", "open my last keynote", "open the trash file", "open trash file",
                   "open delete file", "open downloads", "open home", "empty trash", "show desktop", "home", "delete",
                   "up", "copy", "paste", "select all", "undo", "find", "go back", "new tab", "stop", "cancel"] {
        #expect(grammar.parse(phrase, frontmost: finder) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    for phrase in ["trash", "go to trash"] { #expect(grammar.parse(phrase, frontmost: finder) != chord(.delete), Comment(rawValue: phrase)) }
    for phrase in AppPack.finder.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
}
