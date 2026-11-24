import Foundation

extension AppPack {
    /// Slack desktop shortcuts (help page "Slack keyboard shortcuts", Mac column). Later, sidebar and Home are
    /// unverified chords; upload is ⌘O (older Slack: ⌘U). The global go back/forward, find, escape, full screen and
    /// enter already match Slack and bare mute stays the Mac's volume, so none are repeated. "jump to <name>" is a
    /// typing lead: it opens the quick switcher and types the name, and the user says "enter" to go there.
    static let slack: AppPack = {
        func chord(_ key: Key, _ modifiers: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(key, modifiers))] }
        let cmdShift: Set<Modifier> = [.command, .shift]
        let groups: [([String], [Action])] = [
            (["quick switcher", "switch conversation"], chord(.k)),
            (["new message", "compose", "compose message", "new direct message"], chord(.n)),
            (["direct messages", "dms", "browse dms", "browse direct messages"], chord(.k, cmdShift)),
            (["threads", "show threads"], chord(.t, cmdShift)),
            (["activity", "mentions", "mentions and reactions", "show activity"], chord(.m, cmdShift)),
            (["later", "saved items", "saved messages", "show later"], chord(.s, cmdShift)),
            (["search", "search slack"], chord(.g)),
            (["search this channel", "search in channel", "search this conversation"], chord(.f)),
            (["previous channel", "channel up"], chord(.up, [.option])),
            (["next channel", "channel down"], chord(.down, [.option])),
            (["previous unread", "previous unread channel"], chord(.up, [.option, .shift])),
            (["next unread", "next unread channel"], chord(.down, [.option, .shift])),
            (["all unreads", "unreads", "show unreads"], chord(.a, cmdShift)),
            (["mark all as read", "mark all read", "mark everything read"], chord(.escape, [.shift])),
            (["mark as read", "mark channel read", "mark this channel read"], chord(.escape, [])),
            (["upload a file", "upload file", "attach a file", "attach file"], chord(.o)),
            (["toggle sidebar", "show sidebar", "hide sidebar"], chord(.d, cmdShift)),
            (["huddle", "start huddle", "join huddle", "leave huddle", "end huddle"], chord(.h, cmdShift)),
            (["close panel", "close pane", "close thread", "hide right sidebar"], chord(.period)),
            (["close window", "close slack window"], chord(.w)),
            (["browse channels", "channel browser"], chord(.l, cmdShift)),
            (["people", "show people", "directory"], chord(.e, cmdShift)),
            (["home view", "slack home"], chord(.one, [.control])),
            (["preferences", "slack preferences", "settings"], chord(.comma)),
            (["send", "send message", "send it"], chord(.return, [])),
        ]
        var phrases: [String: [Action]] = [:]
        for (names, actions) in groups { for name in names { phrases[name] = actions } }
        // Send is irreversible: it asks for a spoken yes first (the built-in guarded-verb rule).
        return AppPack(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"], phrases: phrases,
                       confirms: ["send", "send message", "send it"], typingLeads: ["jump to": chord(.k) + [.wait(ms: 300)]])
    }()
}
