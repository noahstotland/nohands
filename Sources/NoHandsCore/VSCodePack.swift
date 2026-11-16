import Foundation

extension AppPack {
    /// VS Code's default macOS keybindings (1.109). Overrides the global new tab, next/previous tab and go back/forward,
    /// whose chords mean something else in VS Code. There is no "stop debugging" phrase: no pack phrase may contain "stop".
    static let vscode: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        let groups: [([String], [Action])] = [
            (["command palette", "show commands", "show all commands"], chord(.p, [.command, .shift])),
            (["quick open", "go to file", "find file"], chord(.p)),
            (["go to line"], chord(.g, [.control])),
            (["go to definition", "definition"], chord(.f12, [])),
            (["find references", "find all references", "go to references", "references"], chord(.f12, [.shift])),
            (["next editor", "next tab"], chord(.right, [.command, .option])),
            (["previous editor", "previous tab"], chord(.left, [.command, .option])),
            (["close editor", "close file"], chord(.w)),
            (["split editor", "split the editor"], chord(.backslash)),
            (["toggle sidebar", "show sidebar", "hide sidebar", "sidebar", "toggle side bar", "show side bar",
              "hide side bar", "side bar"], chord(.b)),
            (["explorer", "show explorer", "file explorer"], chord(.e, [.command, .shift])),
            (["source control", "show source control"], chord(.g, [.control, .shift])),
            (["extensions", "show extensions"], chord(.x, [.command, .shift])),
            (["problems", "show problems"], chord(.m, [.command, .shift])),
            (["save all"], chord(.s, [.command, .option])),
            (["format document", "format file", "format"], chord(.f, [.shift, .option])),
            (["rename symbol", "rename"], chord(.f2, [])),
            (["toggle comment", "comment line", "comment", "uncomment"], chord(.slash)),
            (["move line up"], chord(.up, [.option])),
            (["move line down"], chord(.down, [.option])),
            (["duplicate line", "copy line down"], chord(.down, [.shift, .option])),
            (["find in files", "search in files", "search files"], chord(.f, [.command, .shift])),
            (["replace", "find and replace"], chord(.f, [.command, .option])),
            (["replace in files"], chord(.h, [.command, .shift])),
            (["toggle terminal", "show terminal", "hide terminal"], chord(.grave, [.control])),
            (["new terminal"], chord(.grave, [.control, .shift])),
            (["start debugging", "debug", "continue", "continue debugging"], chord(.f5, [])),
            (["toggle breakpoint", "breakpoint", "add breakpoint", "remove breakpoint"], chord(.f9, [])),
            (["step over"], chord(.f10, [])),
            (["step into", "step in"], [.menuItem("Step Into")]),  // plain F11 is macOS Show Desktop
            (["step out"], chord(.f11, [.shift])),
            (["zen mode", "toggle zen mode", "exit zen mode", "leave zen mode"], chord(.k) + chord(.z, [])),
            (["new window"], chord(.n, [.command, .shift])),
            (["settings", "preferences"], chord(.comma)),
            (["new tab", "new file"], chord(.n)),
            (["go back"], chord(.minus, [.control])),
            (["go forward"], chord(.minus, [.control, .shift])),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        return AppPack(name: "VS Code", bundleIDs: ["com.microsoft.VSCode"], phrases: phrases)
    }()
}
