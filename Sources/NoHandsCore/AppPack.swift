import Foundation

/// A phrase table for one or more apps, checked before the global table while one of its bundle IDs is frontmost.
/// An entry has the shape of a `CommandGrammar` table entry: key chords, or `.menuItem(title)`.
public struct AppPack: Sendable {
    /// The app's name, for the README and logs.
    public let name: String
    public let bundleIDs: Set<String>
    /// Keys are already normalized: lowercase, single spaces, no ASR punctuation.
    public let phrases: [String: [Action]]
    /// Normalized lead phrases that carry a name: "jump to general" runs the lead's actions, then types "general".
    public let typingLeads: [String: [Action]]

    public init(name: String, bundleIDs: Set<String>, phrases: [String: [Action]], typingLeads: [String: [Action]] = [:]) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.phrases = phrases
        self.typingLeads = typingLeads
    }
}

public enum AppPacks {
    /// The shipped packs; each app ticket adds an entry here and a row in docs/voice-commands.md.
    public static let all: [AppPack] = [.terminal, .slack]
}

/// The lead words the grammar drops before a phrase lookup, so "open a new tab" and "go to the downloads" reach
/// the table entries "new tab" and "downloads".
enum PhraseLead {
    enum Dropped: Equatable { case none, open, goTo }

    /// Drops one leading "open" or "go to", then one leading "the", "a" or "an".
    static func strip(_ tokens: [String]) -> (tokens: [String], dropped: Dropped) {
        var rest = tokens[...]
        var dropped = Dropped.none
        if rest.first == "open" {
            rest = rest.dropFirst(); dropped = .open
        } else if rest.count > 1, rest.first == "go", rest[rest.startIndex + 1] == "to" {
            rest = rest.dropFirst(2); dropped = .goTo
        }
        if let article = rest.first, ["the", "a", "an"].contains(article) { rest = rest.dropFirst() }
        return (Array(rest), dropped)
    }
}
