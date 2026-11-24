import Testing
@testable import NoHandsCore

private let chrome = "com.google.Chrome"

@Test func chromePhrasesRunOnlyInChrome() {
    let grammar = CommandGrammar(), chromeOnly = CommandGrammar(packs: [.chrome])
    for (phrase, expected) in AppPack.chrome.phrases {
        for form in [phrase, "open \(phrase)", "open a \(phrase)", "open the \(phrase)"] {
            #expect(grammar.parse(form, frontmost: chrome) == expected, Comment(rawValue: form))
        }
        // Only the Chrome pack: Safari's own pack shares some chords, which is not a leak.
        for app in ["com.apple.Safari", nil] {
            #expect(chromeOnly.parse(phrase, frontmost: app) != expected, Comment(rawValue: phrase))
        }
    }
}

@Test func chromeKeepsOtherOpenPhrasesAndStop() {
    let grammar = CommandGrammar()
    for phrase in ["open chrome", "open safari", "open file budget", "open the downloads folder", "open my last keynote",
                   "open system settings", "close the other tabs", "tab 3", "stop", "cancel"] {
        #expect(grammar.parse(phrase, frontmost: chrome) == grammar.parse(phrase, frontmost: nil), Comment(rawValue: phrase))
    }
    #expect(grammar.parse("open chrome", frontmost: chrome) == [.openApp("chrome")])
    #expect(grammar.parse("open safari", frontmost: chrome) == [.openApp("safari")])
    for phrase in AppPack.chrome.phrases.keys {
        #expect(!StopWords.isStop(phrase) && !phrase.split(separator: " ").contains("stop"), Comment(rawValue: phrase))
    }
}
