import Foundation

extension AppPack {
    /// Chrome 157's macOS menu bar (chords and titles read from the running app). There is no stop-loading phrase (no
    /// pack phrase may contain "stop"; `escape` stops a load), no clear browsing data phrase (its chord is blocked and
    /// the item is titled Delete Browsing Data…), and no translate or reading mode phrase (no menu-bar item). No bare
    /// back, forward or print: a one-word phrase would fire before the rest of a sentence arrived.
    static let chrome: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        let cs: Set<Modifier> = [.command, .shift]
        let co: Set<Modifier> = [.command, .option]
        let groups: [([String], [Action])] = [
            (["new window"], chord(.n)),
            (["new incognito window", "incognito window", "incognito"], chord(.n, cs)),
            (["reopen closed tab", "reopen tab", "reopen last tab", "restore tab"], chord(.t, cs)),
            (["duplicate tab", "duplicate this tab"], [.menuItem("Duplicate Tab")]),
            (["pin tab", "pin this tab"], [.menuItem("Pin Tab")]),
            (["unpin tab", "unpin this tab"], [.menuItem("Unpin Tab")]),
            (["move tab to new window", "move tab to a new window", "move this tab to a new window"],
             [.menuItem("Move Tab to New Window")]),
            (["search tabs", "tab search"], chord(.a, cs)),
            (["hard reload", "force reload", "hard refresh"], chord(.r, cs)),
            (["home page", "go home"], chord(.h, cs)),
            (["find next"], chord(.g)),
            (["find previous"], chord(.g, cs)),
            (["view source", "view page source", "page source"], chord(.u, co)),
            (["developer tools", "dev tools", "devtools"], chord(.i, co)),
            (["javascript console"], chord(.j, co)),
            (["print page", "print this page"], chord(.p)),
            (["save page", "save page as", "save this page"], chord(.s)),
            (["bookmark this page", "bookmark this tab", "bookmark page", "add bookmark"], chord(.d)),
            (["bookmark all tabs"], chord(.d, cs)),
            (["bookmarks bar", "show bookmarks bar", "hide bookmarks bar", "toggle bookmarks bar"], chord(.b, cs)),
            (["bookmark manager", "bookmarks", "manage bookmarks"], chord(.b, co)),
            (["history", "show history", "browsing history"], chord(.y)),
            (["downloads", "show downloads"], chord(.j, cs)),
            (["delete browsing data"], [.menuItem("Delete Browsing Data…")]),
            (["extensions", "show extensions", "manage extensions"], [.menuItem("Extensions")]),
            (["settings", "chrome settings", "preferences"], chord(.comma)),
            (["address bar", "focus address bar", "location bar", "url bar"], chord(.l)),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        return AppPack(name: "Chrome", bundleIDs: ["com.google.Chrome"], phrases: phrases)
    }()
}
