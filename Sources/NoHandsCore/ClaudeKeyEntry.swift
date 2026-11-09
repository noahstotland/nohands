import Foundation

/// Puts a typed Claude API key into the text of `config.json`, keeping every other key.
public enum ClaudeKeyEntry {
    /// Carries no payload: Foundation's parse errors can quote the file, which may hold a key.
    public enum Error: Swift.Error, Equatable, Sendable { case invalidJSON }

    /// The typed text trimmed of whitespace and newlines; nil when nothing is left.
    public static func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// `existing` (nil means no file, treated as `{}`) with `anthropicAPIKey` set to `key`, sorted and pretty-printed
    /// with a trailing newline. Anything that is not a JSON object, an empty file included, throws `invalidJSON`.
    public static func merged(existing: Data?, key: String) throws -> Data {
        var object: [String: Any] = [:]
        if let existing {
            guard let parsed = try? JSONSerialization.jsonObject(with: existing),
                  let dictionary = parsed as? [String: Any] else { throw Error.invalidJSON }
            object = dictionary
        }
        object["anthropicAPIKey"] = key
        guard var out = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { throw Error.invalidJSON }
        out.append(0x0A)
        return out
    }
}
