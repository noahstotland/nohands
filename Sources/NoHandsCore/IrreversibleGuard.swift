import Foundation

/// Finds a step that is about to press an irreversible button (Send, Delete, Place order, ...) the user's goal did
/// not name. The task runner pauses such a step for a spoken yes (`ConfirmAnswer`) instead of running it on a guess.
/// Words are matched whole ("Sender", "Sent" and "Posts" are not buttons to ask about), and each verb is allowed
/// only by its own forms in the goal: "buy a lamp" allows Buy but not Place order.
public enum IrreversibleGuard {
    private struct Verb {
        /// What the user hears in "say yes to ...", and the imperative words the element's name must contain in a row.
        let name: String
        /// Goal words that allow the verb: every set needs one of its words in the goal.
        let allowedBy: [Set<String>]

        init(_ name: String, allowedBy: [Set<String>]) {
            self.name = name
            self.allowedBy = allowedBy
        }
    }

    private static let verbs: [Verb] = [
        Verb("send", allowedBy: [["send", "sends", "sending", "sent"]]),
        Verb("delete", allowedBy: [["delete", "deletes", "deleting", "deleted"]]),
        Verb("remove", allowedBy: [["remove", "removes", "removing", "removed"]]),
        Verb("discard", allowedBy: [["discard", "discards", "discarding", "discarded"]]),
        Verb("pay", allowedBy: [["pay", "pays", "paying", "paid"]]),
        Verb("buy", allowedBy: [["buy", "buys", "buying", "bought"]]),
        Verb("purchase", allowedBy: [["purchase", "purchases", "purchasing", "purchased"]]),
        Verb("checkout", allowedBy: [["checkout"]]),
        Verb("confirm", allowedBy: [["confirm", "confirms", "confirming", "confirmed"]]),
        Verb("submit", allowedBy: [["submit", "submits", "submitting", "submitted"]]),
        Verb("publish", allowedBy: [["publish", "publishes", "publishing", "published"]]),
        Verb("post", allowedBy: [["post", "posts", "posting", "posted"]]),
        Verb("unsubscribe", allowedBy: [["unsubscribe", "unsubscribes", "unsubscribing", "unsubscribed"]]),
        Verb("transfer", allowedBy: [["transfer", "transfers", "transferring", "transferred"]]),
        Verb("place order", allowedBy: [["order", "orders", "ordering", "ordered"]]),
        Verb("empty trash",
             allowedBy: [["empty", "empties", "emptying", "emptied"], ["trash", "bin"]]),
    ]

    /// Letters and digits only, so "Send…" and "File > Send" split into words; "check out" is one word, "checkout".
    private static func words(_ text: String) -> [String] {
        let cleaned = String(text.map { $0.isLetter || $0.isNumber ? $0 : " " })
        var out: [String] = []
        for word in CommandGrammar.normalize(cleaned) {
            if word == "out", out.last == "check" { out[out.count - 1] = "checkout" } else { out.append(word) }
        }
        return out
    }

    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }

    /// The verbs to confirm before `actions` run ("send", or "send and delete" when one step holds several), or nil
    /// when the step may run. One yes then covers exactly the verbs it was asked about.
    public static func held(_ actions: [Action], labels: [Int: UIElementInfo], goal: String) -> String? {
        let goalWords = Set(words(goal))
        var found: [String] = []
        for action in actions {
            guard let name = targetName(of: action, labels: labels) else { continue }
            let nameWords = words(name)
            for verb in verbs where contains(nameWords, words(verb.name)) && !found.contains(verb.name) {
                if !verb.allowedBy.allSatisfy({ !$0.isDisjoint(with: goalWords) }) { found.append(verb.name) }
            }
        }
        return found.isEmpty ? nil : found.joined(separator: " and ")
    }

    /// What the user would call the thing the action presses; nil for an action with no name.
    private static func targetName(of action: Action, labels: [Int: UIElementInfo]) -> String? {
        switch action {
        case .click(.label(let n), _, _), .click(.numbered(let n), _, _): return labels[n]?.title
        case .click(.element(let name), _, _), .clickIn(_, let name): return name
        case .menuItem(let path): return path
        case .setValue(.label(let n), _): return labels[n]?.title
        case .setValue(.named(let name), _): return name
        case .pressKey(let chord) where chord.key == .return:
            return labels.keys.sorted().compactMap { labels[$0] }
                .first { $0.states.contains("focused") && $0.role.lowercased().contains("button") }?.title
        default: return nil
        }
    }
}

/// Whether a spoken reply to "say yes to <verb>" is a yes. Only "yes", "confirm" and "do it" count, with "please"
/// before or after; "yeah", "sure" or a yes with more words after it do not, so a stray word cannot confirm a payment.
public enum ConfirmAnswer {
    /// `attention` is the configured attention word, stripped when the reply starts with it (it is not required).
    public static func isYes(_ transcript: String, attention: AttentionGate = .off) -> Bool {
        var text = transcript
        if case .addressed(let rest) = attention.check(transcript) { text = rest }
        var words = CommandGrammar.normalize(text)
        if words.first == "please" { words.removeFirst() }
        if words.last == "please" { words.removeLast() }
        return ["yes", "confirm", "do it"].contains(words.joined(separator: " "))
    }
}
