import Foundation

extension AppPack {
    /// Finder's own shortcuts (macOS 14.5). Navigation keys are whole `go to` phrases, so NH-58's `open the downloads
    /// folder` and `open trash` are untouched and no bare place name is a key. There is no bare `delete`, `trash`
    /// or `home` (a bare `go to trash` must never trash the selection). `put back` is the menu item, so outside the
    /// Trash it fails instead of pressing command-delete. No trash key may follow "open" or "open the" as an NH-58
    /// phrase ("open the trash file" is a file called trash), so `trash file` and `delete file` are not keys.
    /// Sidebar, path bar, hidden files and Quick Look are toggles.
    static let finder: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        var confirms = Set<String>()
        // Phrases that wait for a spoken yes before they run.
        func asking(_ names: [String]) -> [String] { confirms.formUnion(names); return names }
        let groups: [([String], [Action])] = [
            (["new window", "new finder window"], chord(.n)),
            (["new folder", "make a new folder", "make new folder", "create a folder", "create folder", "create a new folder"],
             chord(.n, [.command, .shift])),
            (["close window", "close the window", "close finder window"], [.menuItem("File > Close Window")]),
            (["go to folder", "go to a folder"], chord(.g, [.command, .shift])),
            (["go up", "go up a folder", "go up one folder", "up a folder", "up one folder", "go to the parent folder",
              "go to parent folder", "go to the enclosing folder", "go to enclosing folder"], chord(.up)),
            (["icon view", "view as icons", "as icons"], chord(.one)),
            (["list view", "view as list", "as list"], chord(.two)),
            (["column view", "view as columns", "as columns"], chord(.three)),
            (["gallery view", "view as gallery", "as gallery"], chord(.four)),
            (["show sidebar", "hide sidebar", "toggle sidebar"], chord(.s, [.command, .control])),
            (["show path bar", "hide path bar", "toggle path bar"], chord(.p, [.command, .option])),
            (["get info", "show info", "info"], chord(.i)),
            (["open", "open it", "open this", "open selection", "open selected", "open the selection"], chord(.o)),
            (["quick look", "quick look this", "preview this", "close quick look"], chord(.space, [])),
            (["duplicate", "duplicate this", "duplicate it", "duplicate file"], chord(.d)),
            (["make alias", "make an alias", "create alias", "create an alias"], [.menuItem("File > Make Alias")]),
            (["rename", "rename this", "rename it", "rename file", "rename this file"], chord(.return, [])),
            (["move here", "move it here", "move items here", "move them here", "paste as move", "paste here as a move"],
             chord(.v, [.command, .option])),
            (asking(["move to trash", "move to the trash", "move it to the trash", "move it to trash", "move this to the trash",
                     "trash this", "trash it", "trash this file", "delete this file"]), chord(.delete)),
            (["put back", "put it back"], [.menuItem("File > Put Back")]),
            (["show hidden files", "hide hidden files", "toggle hidden files"], chord(.period, [.command, .shift])),
            (["search", "search finder", "search files"], chord(.f)),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        let places: [([String], Key, Set<Modifier>)] = [
            (["home"], .h, [.command, .shift]), (["desktop"], .d, [.command, .shift]),
            (["documents"], .o, [.command, .shift]), (["downloads"], .l, [.command, .option]),
            (["applications", "apps"], .a, [.command, .shift]), (["icloud drive", "icloud"], .i, [.command, .shift]),
        ]
        for (names, key, modifiers) in places {
            for name in names {
                for form in ["X", "the X", "my X", "X folder", "the X folder", "my X folder"] {
                    phrases["go to " + form.replacingOccurrences(of: "X", with: name)] = chord(key, modifiers)
                }
            }
        }
        phrases["go home"] = chord(.h, [.command, .shift])
        return AppPack(name: "Finder", bundleIDs: ["com.apple.finder"], phrases: phrases, confirms: confirms)
    }()
}
