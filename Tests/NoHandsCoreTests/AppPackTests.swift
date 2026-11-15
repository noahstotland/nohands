import Testing
import Foundation
@testable import NoHandsCore

private let cmdT: [Action] = [.pressKey(KeyChord(.t, [.command]))]
private let cmdShiftT: [Action] = [.pressKey(KeyChord(.t, [.command, .shift]))]
private let chrome = AppPack(name: "Chrome", bundleIDs: ["com.google.Chrome", "com.google.Chrome.beta"], phrases: [
    "new tab": cmdShiftT,                       // overrides the global phrase for Chrome only
    "bookmark this page": [.menuItem("Bookmark This Tab…")],
    "downloads": [.menuItem("Downloads")],
])
private let packed = CommandGrammar(packs: [chrome])

@Test func packPhraseRunsOnlyInItsApp() {
    let cases: [(String, String?, [Action]?)] = [
        ("bookmark this page", "com.google.Chrome", [.menuItem("Bookmark This Tab…")]),
        ("bookmark this page", "com.google.Chrome.beta", [.menuItem("Bookmark This Tab…")]),
        ("bookmark this page", "com.apple.Safari", nil),
        ("bookmark this page", nil, nil),
        ("new tab", "com.google.Chrome", cmdShiftT),       // pack overrides the global phrase there
        ("new tab", "com.apple.Safari", cmdT),             // and nowhere else
        ("new tab", nil, cmdT),
        ("go to sleep", "com.google.Chrome", [.setMode(.sleep)]),
    ]
    for (phrase, app, expected) in cases {
        #expect(packed.parse(phrase, frontmost: app) == expected, "\(phrase) in \(app ?? "no app")")
    }
}

@Test func leadWordsReachTheSameEntry() {
    // "open"/"go to"/an article are dropped before the pack lookup.
    for phrase in ["new tab", "open a new tab", "go to the new tab", "open new tab"] {
        #expect(packed.parse(phrase, frontmost: "com.google.Chrome") == cmdShiftT, Comment(rawValue: phrase))
    }
    #expect(packed.parse("open the downloads", frontmost: "com.google.Chrome") == [.menuItem("Downloads")])
    // No pack in front: "open <global phrase>" is that phrase, an unknown app is still opened, "go to" keeps its meaning.
    #expect(g.parse("open a new tab") == cmdT)
    #expect(g.parse("open notes") == [.openApp("notes")])
    #expect(g.parse("go to the new tab") == [.pressKey(KeyChord(.l, [.command])), .typeText("the new tab"), .pressKey(KeyChord(.return))])
    #expect(g.parse("go to youtube") == [.openURL(URL(string: "https://www.youtube.com")!, app: nil)])
}

@Test func menuWordsBecomeAMenuItem() {
    #expect(g.parse("menu Save As…") == [.menuItem("Save As…")])
    #expect(g.parse("menu bookmark this tab") == [.menuItem("bookmark this tab")])
    #expect(g.parse("menu") == nil)
}

@Test func stopNeverMatchesAPack() {
    let hostile = CommandGrammar(packs: [AppPack(name: "X", bundleIDs: ["x"], phrases: ["stop": cmdT, "cancel": cmdT])])
    #expect(hostile.parse("stop", frontmost: "x") == nil)
    #expect(hostile.parse("Cancel.", frontmost: "x") == g.parse("cancel"))   // the global phrase, not the pack's
}

@Test func shippedPacksAreWellFormed() {
    for pack in AppPacks.all {
        #expect(!pack.bundleIDs.isEmpty, Comment(rawValue: pack.name))
        for (phrase, actions) in pack.phrases {
            #expect(!actions.isEmpty, "\(pack.name): \(phrase)")
            #expect(!StopWords.isStop(phrase), "\(pack.name): \(phrase) is a stop word")
            #expect(CommandGrammar.normalize(phrase).joined(separator: " ") == phrase, "\(pack.name): \(phrase) is not normalized")
        }
    }
}
