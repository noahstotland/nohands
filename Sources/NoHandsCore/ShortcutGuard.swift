import Foundation

/// Code-level safety net for the task loop: a model step may not close a tab/window (command-w) or quit an app
/// (command-q) unless the user's goal asks to close or quit something.
public enum ShortcutGuard {
    private static let guardedKeys: [Key] = [.w, .q]
    private static let allowWords = ["close", "quit", "exit", "shut"]

    /// A failure message when `actions` contain a guarded chord the goal does not ask for; nil when allowed.
    public static func blocked(_ actions: [Action], goal: String) -> String? {
        let words = CommandGrammar.normalize(goal)
        if words.contains(where: { w in allowWords.contains { w.hasPrefix($0) } }) { return nil }
        for action in actions {
            if case .pressKey(let chord) = action, chord.modifiers.contains(.command), guardedKeys.contains(chord.key) {
                return "blocked: command-\(chord.key.rawValue) not allowed for this request"
            }
        }
        return nil
    }
}
