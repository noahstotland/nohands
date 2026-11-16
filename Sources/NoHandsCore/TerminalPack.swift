import Foundation

extension AppPack {
    /// Terminal's own window, scrollback and font shortcuts (macOS 14.5 menu file). The global new tab, close tab,
    /// close window, next/previous tab, find and page up/down already match Terminal's chords, so they are not repeated.
    static let terminal: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        let groups: [([String], [Action])] = [
            (["new window", "new terminal window"], chord(.n)),
            (["clear", "clear all", "clear terminal"], chord(.k)),
            (["clear screen"], chord(.l, [.command, .control])),
            (["clear scrollback", "clear the scrollback", "clear history"], chord(.k, [.command, .option])),
            (["scroll to top", "scroll to the top"], chord(.home)),
            (["scroll to bottom", "scroll to the bottom"], chord(.end)),
            (["split pane", "split window", "split the window"], chord(.d)),
            (["close pane", "close split pane", "close the split pane"], chord(.d, [.command, .shift])),
            (["bigger font", "font bigger", "increase font size", "bigger text", "make text bigger",
              "make the text bigger", "larger text"], chord(.equal, [.command, .shift])),
            (["smaller font", "font smaller", "decrease font size", "smaller text", "make text smaller",
              "make the text smaller"], chord(.minus)),
            (["default font size", "reset font size", "normal font size"], chord(.zero)),
            (["interrupt", "interrupt command", "cancel command", "send control c"], chord(.c, [.control])),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        return AppPack(id: "terminal", name: "Terminal", author: "NoHands", bundleIDs: ["com.apple.Terminal"], phrases: phrases)
    }()
}
