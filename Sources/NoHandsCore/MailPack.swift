import Foundation

extension AppPack {
    /// Mail's own message shortcuts (macOS 14.5 menu titles). Read, flag, junk and the mailbox list use Mail's toggle
    /// chords, since their menu titles flip with the selection. Every send and delete phrase (a bare `send` too) asks
    /// for a spoken yes first. The global `delete`, `up`, `down`, `undo` and `find` are not repeated, so editing a reply
    /// works as in every other app.
    static let mail: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        var confirms = Set<String>()
        // Phrases that wait for a spoken yes before they run.
        func asking(_ names: [String]) -> [String] { confirms.formUnion(names); return names }
        let groups: [([String], [Action])] = [
            (["new message", "new email", "new mail", "compose", "compose message", "compose email"], chord(.n)),
            (["reply", "reply to this", "reply to message", "reply to the message"], chord(.r)),
            (["reply all", "reply to all"], chord(.r, [.command, .shift])),
            (["forward", "forward this", "forward message", "forward the message"], chord(.f, [.command, .shift])),
            (asking(["send", "send message", "send the message", "send this message", "send email", "send the email",
                     "send this email", "send mail"]), chord(.d, [.command, .shift])),
            (["undo send"], chord(.z)),
            (["next message", "next email"], chord(.down, [])),
            (["previous message", "previous email", "last message"], chord(.up, [])),
            (["get new mail", "get mail", "check mail", "check for new mail", "check email"], chord(.n, [.command, .shift])),
            (["mark as read", "mark read", "mark as unread", "mark unread"], chord(.u, [.command, .shift])),
            (["flag", "flag message", "flag this", "unflag", "unflag message"], chord(.l, [.command, .shift])),
            (["archive", "archive message", "archive this", "archive it"], chord(.a, [.command, .control])),
            (["move to junk", "junk", "mark as junk", "junk message"], chord(.j, [.command, .shift])),
            (asking(["delete message", "delete this message", "delete the message", "delete email", "delete this email",
                     "trash message", "move to trash"]), chord(.delete)),
            (["show mailboxes", "hide mailboxes", "mailbox list", "show mailbox list", "hide mailbox list"],
             chord(.m, [.command, .shift])),
            (["inbox", "inbox mailbox"], chord(.one)),
            // Sent has no fixed chord (command-2 and up follow the Favorites bar), so it is found by title.
            (["sent", "sent mail", "sent mailbox", "sent messages"], [.menuItem("Mailbox > Go to Favorite Mailbox > Sent")]),
            (["search mail", "search mailbox", "search email"], chord(.f, [.command, .option])),
            (["attach a file", "attach file", "attach files", "add attachment", "attach"], chord(.a, [.command, .shift])),
            (["close message", "close email", "close this message"], chord(.w)),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        return AppPack(name: "Mail", bundleIDs: ["com.apple.mail"], phrases: phrases, confirms: confirms)
    }()
}
