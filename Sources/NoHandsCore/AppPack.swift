import Foundation

/// A phrase table for one or more apps, checked before the global table while one of its bundle IDs is frontmost.
/// An entry has the shape of a `CommandGrammar` table entry: key chords, or `.menuItem(title)`.
public struct AppPack: Sendable, Equatable {
    /// Lowercase letters, digits and `-`; the folder name of an installed pack. Built-in packs have fixed ids.
    public let id: String
    /// The app's name, for the README and logs.
    public let name: String
    public let version: String
    public let author: String
    public let bundleIDs: Set<String>
    /// Keys are already normalized: lowercase, single spaces, no ASR punctuation.
    public let phrases: [String: [Action]]

    /// `id` defaults to the name in id form ("Bear Notes" is "bear-notes").
    public init(id: String? = nil, name: String, version: String = "1.0.0", author: String = "",
                bundleIDs: Set<String>, phrases: [String: [Action]]) {
        self.id = id ?? name.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
            .reduce(into: "") { $0.append($1) }
        self.name = name
        self.version = version
        self.author = author
        self.bundleIDs = bundleIDs
        self.phrases = phrases
    }
}

public enum AppPacks {
    /// The shipped packs; each app ticket adds an entry here and a row in docs/voice-commands.md.
    public static let all: [AppPack] = [.terminal, .vscode, .mail, .messages]
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
