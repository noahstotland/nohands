import Foundation

extension AppPack {
    /// Safari's own shortcuts (Safari 17.5 menu titles). The global browser phrases (new tab, close tab, reload, go back,
    /// zoom, `tab 3`) already press Safari's chords, so they are not repeated here. Sidebar, bookmarks, Reading List,
    /// Reader, favorites bar and Tab Overview use toggle chords, since their menu titles flip between Show and Hide.
    /// `view source` needs Safari's "Show features for web developers". No phrase says "stop"; `escape` stops a load.
    static let safari: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        let groups: [([String], [Action])] = [
            (["new window", "new safari window"], chord(.n)),
            (["new private window", "private window", "private browsing window"], chord(.n, [.command, .shift])),
            (["reopen closed tab", "reopen last closed tab", "reopen tab", "undo close tab", "restore tab",
              "reopen closed window", "reopen last closed window"], chord(.t, [.command, .shift])),
            (["address bar", "focus address bar", "open location", "search bar", "smart search field"], chord(.l)),
            (["bookmark this page", "bookmark page", "bookmark this", "add bookmark"], chord(.d)),
            (["show bookmarks", "hide bookmarks", "bookmarks", "bookmarks sidebar", "show bookmarks sidebar"],
             chord(.one, [.command, .control])),
            (["edit bookmarks", "bookmark editor", "all bookmarks"], chord(.b, [.command, .option])),
            (["add to reading list", "save to reading list", "read later"], chord(.d, [.command, .shift])),
            (["show reading list", "hide reading list", "reading list"], chord(.two, [.command, .control])),
            (["show history", "history", "show all history", "browsing history"], chord(.y)),
            (["show downloads", "downloads", "safari downloads"], chord(.l, [.command, .option])),
            (["tab overview", "show tab overview", "hide tab overview", "show all tabs", "all tabs"],
             chord(.backslash, [.command, .shift])),
            (["show sidebar", "hide sidebar", "toggle sidebar", "sidebar"], chord(.l, [.command, .shift])),
            (["reader", "reader view", "reader mode", "show reader", "hide reader"], chord(.r, [.command, .shift])),
            (["favorites bar", "show favorites bar", "hide favorites bar", "favourites bar"], chord(.b, [.command, .shift])),
            (["hard reload", "hard refresh", "reload from origin", "reload page from origin", "reload without cache"],
             chord(.r, [.command, .option])),
            (["view source", "view page source", "show page source", "page source"], chord(.u, [.command, .option])),
            (["print page", "print this page", "print the page"], chord(.p)),
            (["home page", "safari home page"], chord(.h, [.command, .shift])),
            (["move tab to new window"], [.menuItem("Move Tab to New Window")]),
            (["merge all windows", "merge windows"], [.menuItem("Merge All Windows")]),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        return AppPack(name: "Safari", bundleIDs: ["com.apple.Safari"], phrases: phrases)
    }()
}
