import Testing
@testable import NoHandsCore

private func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
private let code = "com.microsoft.VSCode"
private let cs: Set<Modifier> = [.command, .shift]
private let packOnly: [(String, [Action])] = [
    ("command palette", chord(.p, cs)), ("quick open", chord(.p)), ("go to line", chord(.g, [.control])),
    ("go to definition", chord(.f12, [])), ("find references", chord(.f12, [.shift])), ("close file", chord(.w)),
    ("next editor", chord(.right, [.command, .option])), ("split the editor", chord(.backslash)), ("hide side bar", chord(.b)),
    ("open the explorer", chord(.e, cs)), ("source control", chord(.g, [.control, .shift])), ("show extensions", chord(.x, cs)),
    ("go to the problems", chord(.m, cs)), ("save all", chord(.s, [.command, .option])), ("format document", chord(.f, [.shift, .option])),
    ("rename symbol", chord(.f2, [])), ("comment line", chord(.slash)), ("move line up", chord(.up, [.option])),
    ("move line down", chord(.down, [.option])), ("duplicate line", chord(.down, [.shift, .option])),
    ("search in files", chord(.f, cs)), ("find and replace", chord(.f, [.command, .option])), ("replace in files", chord(.h, cs)),
    ("show terminal", chord(.grave, [.control])), ("new terminal", chord(.grave, [.control, .shift])),
    ("continue debugging", chord(.f5, [])), ("toggle breakpoint", chord(.f9, [])), ("step over", chord(.f10, [])),
    ("step into", [.menuItem("Step Into")]), ("step out", chord(.f11, [.shift])), ("exit zen mode", chord(.k) + chord(.z, [])),
    ("new window", chord(.n, cs)), ("open settings", chord(.comma)),
    // Globals the pack overrides.
    ("new tab", chord(.n)), ("open a new tab", chord(.n)), ("previous tab", chord(.left, [.command, .option])),
    ("go back", chord(.minus, [.control])), ("go forward", chord(.minus, [.control, .shift])),
]
private let globals: [(String, [Action])] = [
    ("save", chord(.s)), ("find", chord(.f)), ("close tab", chord(.w)), ("close window", chord(.w, cs)),
    ("full screen", chord(.f, [.command, .control])),
]

@Test func vscodePhrasesRunOnlyInVSCode() {
    let grammar = CommandGrammar()
    for (phrase, expected) in packOnly + globals { #expect(grammar.parse(phrase, frontmost: code) == expected, Comment(rawValue: phrase)) }
    // Every shipped phrase, not just the samples: it runs in VS Code and is not that action anywhere else.
    for (phrase, expected) in AppPack.vscode.phrases {
        #expect(grammar.parse(phrase, frontmost: code) == expected, Comment(rawValue: phrase))
        #expect(grammar.parse(phrase, frontmost: "com.apple.Safari") != expected, Comment(rawValue: phrase))
    }
    for (phrase, expected) in packOnly {
        for app in ["com.apple.Safari", "com.apple.Terminal", nil] {
            #expect(grammar.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase))
        }
    }
}

@Test func vscodeHasNoStopPhraseAndKeepsTheTextEdit() {
    for phrase in AppPack.vscode.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
    let grammar = CommandGrammar()
    for phrase in ["stop", "cancel", "cancel that"] {
        #expect(grammar.parse(phrase, frontmost: code) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    // A bare verb is a complete command and would fire before the rest of a sentence, so none is a pack phrase.
    for phrase in ["replace", "rename", "format", "comment", "debug", "continue"] {
        #expect(grammar.parse(phrase, frontmost: code) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    let edit = grammar.parse("replace foo with bar", frontmost: code, textFocused: true)
    #expect(edit == grammar.parse("replace foo with bar", frontmost: nil, textFocused: true) && edit != chord(.f, [.command, .option]))
}
