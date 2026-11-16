import Testing
@testable import NoHandsCore

private func item(_ title: String, _ path: [String] = ["File"], enabled: Bool = true, sub: Bool = false) -> MenuEntry {
    MenuEntry(title: title, path: path, enabled: enabled, hasSubmenu: sub)
}

private let entries = [
    item("New Tab"), item("New Window"), item("New Incognito Window"),
    item("Save As…"), item("Save"), item("Close Tab", ["File"], enabled: false),
    item("Bookmark This Tab…", ["Bookmarks"]), item("Bookmark All Tabs…", ["Bookmarks"]),
    item("Find", ["Edit"], sub: true), item("Find…", ["Edit", "Find"]), item("Find Next", ["Edit", "Find"]), item("Don't Save", ["Edit"]),
    item("Zoom", ["Window"]), item("Zoom In", ["View"]),
]

@Test func menuMatchPicksTheNamedItemOrNothing() {
    // (spoken, title of the expected entry or nil)
    let cases: [(String, String?)] = [
        ("save as", "Save As…"),               // ellipsis folds away
        ("SAVE AS...", "Save As…"),            // case, and ASR's three dots
        ("save", "Save"),                      // exact beats starts-with ("Save As…" is longer anyway)
        ("new", "New Tab"),                    // starts-with: shortest title, then menu order
        ("bookmark this", "Bookmark This Tab…"),
        ("bookmark tab", "Bookmark This Tab…"),   // contains-all; "tab" is not a whole word of "Tabs"
        ("incognito window", "New Incognito Window"),   // contains-all tier
        ("window incognito", "New Incognito Window"),
        ("dont save", "Don't Save"),           // apostrophes fold away
        ("shut down", nil),                    // nothing close: no guess
        ("sav", nil),                          // a partial word is not a word
        ("", nil),
        ("zoom", "Zoom"),                      // exact in the Window menu beats "Zoom In"
        ("file > save as", "Save As…"),        // a path limits the menu
        ("edit > save as", nil),               // ...so the same words in another menu find nothing
        ("edit > find > find next", "Find Next"),
        ("view > zoom", "Zoom In"),
        ("find", "Find…"),                     // the submenu parent is skipped for the command inside it
        ("close tab", "Close Tab"),            // disabled entries are still returned: the caller says it is disabled
    ]
    // The model's steps match the exact title only, so "trash" cannot press "Empty Trash…".
    let all = entries + [item("Move to Trash"), item("Empty Trash…")]
    #expect(MenuMatch.firstMatch("trash", in: all).map { all[$0].title } == "Empty Trash…")
    #expect(MenuMatch.firstMatch("trash", in: all, exactOnly: true) == nil)
    // ...and the guards read the name as written: characters the loose fold deletes do not make a match.
    for sneaky in ["emp'ty trash", "empty tra...sh", "e`mpty trash"] {
        #expect(MenuMatch.firstMatch(sneaky, in: all, exactOnly: true) == nil, Comment(rawValue: sneaky))
    }
    #expect(MenuMatch.firstMatch("Empty Trash...", in: all, exactOnly: true).map { all[$0].title } == "Empty Trash…")
    #expect(MenuMatch.firstMatch("move to trash", in: all, exactOnly: true).map { all[$0].title } == "Move to Trash")
    for (spoken, title) in cases {
        let found = MenuMatch.firstMatch(spoken, in: entries).map { entries[$0].title }
        #expect(found == title, Comment(rawValue: "menu \(spoken)"))
    }
    let closed = MenuMatch.firstMatch("close tab", in: entries).map { entries[$0] }
    #expect(closed?.enabled == false)
}

@Test func exactOnlyNeverPicksALongerTitleAndLookalikesNeverMatch() {
    let sends = [item("Send Again"), item("Again")]
    #expect(MenuMatch.firstMatch("Again", in: [item("Send Again")], exactOnly: true) == nil)
    #expect(MenuMatch.firstMatch("Again", in: sends, exactOnly: true) == 1)
    #expect(MenuMatch.firstMatch("Save", in: [item("S\u{0430}ve")]) == nil)   // Cyrillic а
    // (title, lookalike): an ASCII title in disguise is one; a real non-English title is not.
    let cases: [(String, Bool)] = [
        ("S\u{0430}ve", true), ("\u{FF31}\u{FF55}\u{FF49}\u{FF54}", true), ("\u{1D412}end", true), ("Save…", false), ("Emoji & Symbols", false),
        ("Enregistrer sous…", false), ("Envoyer \u{00E0} nouveau", false), ("Закрыть Safari", false), ("Safari を終了", false),
        ("S\u{0435}nd \u{00C4}gain", true), ("S\u{0435}nd\u{3092}", true), ("URLを開く", false),
    ]
    for (title, expected) in cases { #expect(MenuMatch.isLookalike(title) == expected, Comment(rawValue: title)) }
}
