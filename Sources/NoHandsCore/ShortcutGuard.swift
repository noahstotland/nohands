import Foundation

/// Code-level safety net for the task loop: a model step may not close a tab/window (command-w) or quit an app
/// (command-q) unless the user's goal asks for that specific thing. Words are matched exactly (no prefixes), so
/// "quite" or "closet" allow nothing, and "close this tab" allows command-w but not command-q.
public enum ShortcutGuard {
    /// Goal words that allow each guarded key. "shut" allows both ("shut the tab", "shut down Slack").
    private static let allowWords: [Key: Set<String>] = [
        .w: ["close", "closes", "closing", "closed", "shut"],
        .q: ["quit", "quits", "quitting", "exit", "exiting", "shut"],
    ]

    /// `close_app` quits: it needs a quit word or a close word.
    private static let closeAppWords: Set<String> = allowWords[.w]!.union(allowWords[.q]!)

    /// Whether the goal has a close word (the list command-w uses); `TabGuard` closes tabs on the same words.
    static func allowsClose(goal: String) -> Bool {
        !allowWords[.w]!.isDisjoint(with: Set(CommandGrammar.normalize(goal)))
    }

    /// A failure message when `actions` contain a guarded chord (or a `close_app`) the goal does not ask for;
    /// nil when allowed.
    public static func blocked(_ actions: [Action], goal: String) -> String? {
        let words = Set(CommandGrammar.normalize(goal))
        for action in actions {
            switch action {
            case .pressKey(let chord):
                guard chord.modifiers.contains(.command), let allowed = allowWords[chord.key] else { continue }
                if allowed.isDisjoint(with: words) {
                    return "blocked: command-\(chord.key.rawValue) not allowed for this request"
                }
            case .closeApp:
                if closeAppWords.isDisjoint(with: words) { return "blocked: close_app not allowed for this request" }
            default:
                continue
            }
        }
        return nil
    }
}
