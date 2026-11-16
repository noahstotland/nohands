import Foundation

extension AppPack {
    /// Messages' own shortcuts and menu items (macOS 14.5 menu bar). There is no "send" phrase (`enter` sends) and no
    /// pin phrase (pin has no menu item or shortcut). "delete conversation" only opens Messages' own confirm.
    static let messages: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        let groups: [([String], [Action])] = [
            (["new message", "new conversation", "new chat", "compose", "compose message", "start new message",
              "start a new message"], chord(.n)),
            (["next conversation", "next chat", "next message thread"], chord(.tab, [.control])),
            (["previous conversation", "previous chat", "last conversation"], chord(.tab, [.control, .shift])),
            (["search", "search messages", "search conversations", "find conversation"], chord(.f)),
            (["show details", "details", "conversation details", "show info", "info"], chord(.i)),
            (["mark as unread", "mark unread", "mark conversation as unread"], [.menuItem("Mark as Unread")]),
            (["mark as read", "mark read", "mark conversation as read"], [.menuItem("Mark as Read")]),
            (["emoji", "add emoji", "emoji picker", "show emoji"], [.menuItem("Emoji & Symbols")]),
            (["tapback", "add tapback", "react", "tapback message"], chord(.t)),
            (["close window", "close conversation window"], chord(.w)),
            (["delete conversation", "delete this conversation", "delete the conversation"],
             [.menuItem("Delete Conversation…")]),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        return AppPack(name: "Messages", bundleIDs: ["com.apple.MobileSMS"], phrases: phrases)
    }()
}
