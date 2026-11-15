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
    #expect(MenuMatch.firstMatch("move to trash", in: all, exactOnly: true).map { all[$0].title } == "Move to Trash")
    for (spoken, title) in cases {
        let found = MenuMatch.firstMatch(spoken, in: entries).map { entries[$0].title }
        #expect(found == title, Comment(rawValue: "menu \(spoken)"))
    }
    let closed = MenuMatch.firstMatch("close tab", in: entries).map { entries[$0] }
    #expect(closed?.enabled == false)
}
