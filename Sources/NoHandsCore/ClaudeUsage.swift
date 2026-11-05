import Foundation

/// Token counts from a Messages API response's `usage` block. Numbers only; no response text is read.
public struct ClaudeUsage: Equatable, Sendable {
    /// Input tokens after the last cache breakpoint (not read from or written to the cache).
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int

    public init(inputTokens: Int, cacheReadTokens: Int, cacheWriteTokens: Int) {
        self.inputTokens = inputTokens; self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens
    }

    /// nil when the response is not a JSON object with a `usage` object; a missing count reads as 0.
    public static func from(response data: Data) -> ClaudeUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else { return nil }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        return ClaudeUsage(inputTokens: count("input_tokens"), cacheReadTokens: count("cache_read_input_tokens"),
                           cacheWriteTokens: count("cache_creation_input_tokens"))
    }

    /// `cache=<read>/<written> in=<uncached input>`, or `cache=-` without usage. Counts only.
    public static func logFragment(_ usage: ClaudeUsage?) -> String {
        guard let u = usage else { return "cache=-" }
        return "cache=\(u.cacheReadTokens)/\(u.cacheWriteTokens) in=\(u.inputTokens)"
    }
}
