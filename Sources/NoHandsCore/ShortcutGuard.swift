import Foundation

/// Code-level safety net for the task loop: a model step may not close a tab/window (command-w) or quit an app
/// (command-q), or run the same through its menu item ("Close Window", "Quit Safari"), unless the user's goal asks for that specific thing. Words are matched exactly (no prefixes), so
/// "quite" or "closet" allow nothing, and "close this tab" allows command-w but not command-q.
public enum ShortcutGuard {
    /// Goal words that allow each guarded key. "shut" allows both ("shut the tab", "shut down Slack").
    private static let allowWords: [Key: Set<String>] = [
        .w: ["close", "closes", "closing", "closed", "shut"],
        .q: ["quit", "quits", "quitting", "exit", "exiting", "shut"],
    ]

    /// Words in a menu item's title that make it the menu form of each guarded chord.
    private static let titleWordsFor: [Key: Set<String>] = [
        .w: ["close", "closes", "closing", "shut"],
        .q: ["quit", "quits", "quitting", "shut"],
    ]

    /// `close_app` quits: it needs a quit word or a close word.
    private static let closeAppWords: Set<String> = allowWords[.w]!.union(allowWords[.q]!)

    /// Whether the goal has a close word (the list command-w uses); `TabGuard` closes tabs on the same words.
    static func allowsClose(goal: String) -> Bool {
        !allowWords[.w]!.isDisjoint(with: IrreversibleGuard.goalVerbs(goal))
    }

    /// A failure message when `actions` contain a guarded chord (or a `close_app`) the goal does not ask for;
    /// nil when allowed.
    public static func blocked(_ actions: [Action], goal: String) -> String? {
        // A word after a negation in its clause ("don't quit Safari") asks for nothing.
        let words = IrreversibleGuard.goalVerbs(goal)
        for action in actions {
            switch action {
            case .pressKey(let chord):
                guard chord.modifiers.contains(.command), let allowed = allowWords[chord.key] else { continue }
                if allowed.isDisjoint(with: words) {
                    return "blocked: command-\(chord.key.rawValue) not allowed for this request"
                }
            case .closeApp:
                if closeAppWords.isDisjoint(with: words) { return "blocked: close_app not allowed for this request" }
            case .menuItem(let title, _):
                if let why = menuTitleBlocked(title, words: words) { return why }
            case .clickIn(.menubar, let name):
                // The same menu items as `menu_item`, reached by a different step: an Apple menu item or a lookalike
                // is refused whatever the goal says, and a quit or close title needs its goal word.
                if MenuMatch.isAppleMenuTitle(MenuMatch.leaf(of: name) ?? name) || MenuMatch.isLookalike(name) {
                    return "blocked: \(name) is an Apple menu item"
                }
                if let why = menuTitleBlocked(name, words: words) { return why }
            default:
                continue
            }
        }
        return nil
    }

    /// "Close Window", "Quit Chrome": the menu form of the guarded chords asks the same of the goal. Split like
    /// IrreversibleGuard does (every non letter or digit is a break), so "File>Close Window" and "Close…" are seen.
    /// "Exit Full Screen" and "Reopen Closed Tab" are not close or quit commands.
    private static func menuTitleBlocked(_ title: String, words: Set<String>) -> String? {
        let titleWords = Set(title.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }.split(separator: " ").map(String.init))
        for (key, allowed) in allowWords where !titleWordsFor[key]!.isDisjoint(with: titleWords) && allowed.isDisjoint(with: words) {
            return "blocked: menu item \(title) not allowed for this request"
        }
        return nil
    }
}
