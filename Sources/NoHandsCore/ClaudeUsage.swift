import Foundation

/// Token counts from a Messages API response's `usage` block. Numbers only; no response text is read.
public struct ClaudeUsage: Equatable, Sendable {
    /// Input tokens after the last cache breakpoint (not read from or written to the cache).
    public var inputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, cacheReadTokens: Int, cacheWriteTokens: Int, outputTokens: Int = 0) {
        self.inputTokens = inputTokens; self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens
        self.outputTokens = outputTokens
    }

    /// nil when the response is not a JSON object with a `usage` object; a missing count reads as 0.
    public static func from(response data: Data) -> ClaudeUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else { return nil }
        func count(_ key: String) -> Int { (usage[key] as? NSNumber)?.intValue ?? 0 }
        return ClaudeUsage(inputTokens: count("input_tokens"), cacheReadTokens: count("cache_read_input_tokens"),
                           cacheWriteTokens: count("cache_creation_input_tokens"), outputTokens: count("output_tokens"))
    }

    /// `cache=<read>/<written> in=<uncached input> out=<output>`, or `cache=-` without usage. Counts only.
    public static func logFragment(_ usage: ClaudeUsage?) -> String {
        guard let u = usage else { return "cache=-" }
        return "cache=\(u.cacheReadTokens)/\(u.cacheWriteTokens) in=\(u.inputTokens) out=\(u.outputTokens)"
    }
}

extension Int {
    /// `self + other`, clamped to `Int.max` or `Int.min` instead of trapping on overflow.
    func saturatingAdd(_ other: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(other)
        return overflow ? (other > 0 ? .max : .min) : sum
    }
}

/// Running sum of the Claude calls made in one app session. Counts only; no text ever reaches it.
public struct ClaudeUsageTotal: Equatable, Sendable {
    public private(set) var calls = 0
    public private(set) var input = 0
    public private(set) var cacheRead = 0
    public private(set) var cacheWrite = 0
    public private(set) var output = 0

    public init() {}

    /// Adds one call. A call with no `usage` object (nil) still counts as a call, with zero tokens.
    public func adding(_ usage: ClaudeUsage?) -> ClaudeUsageTotal {
        var t = self
        t.calls = t.calls.saturatingAdd(1)
        if let u = usage {
            t.input = t.input.saturatingAdd(u.inputTokens); t.cacheRead = t.cacheRead.saturatingAdd(u.cacheReadTokens)
            t.cacheWrite = t.cacheWrite.saturatingAdd(u.cacheWriteTokens); t.output = t.output.saturatingAdd(u.outputTokens)
        }
        return t
    }

    /// `Claude this session: 14 calls, 31k in, 9k cached, 2k out`; nil before the first call.
    /// "in" is uncached input plus cache writes (both billed as fresh input); "cached" is cache reads.
    public var menuLine: String? {
        guard calls > 0 else { return nil }
        return "Claude this session: \(calls) \(calls == 1 ? "call" : "calls"), \(Self.short(input.saturatingAdd(cacheWrite))) in, "
            + "\(Self.short(cacheRead)) cached, \(Self.short(output)) out"
    }

    /// `calls=<n> in=<uncached> cache=<read>/<written> out=<output>`. Numbers only.
    public var logFragment: String {
        "calls=\(calls) in=\(input) cache=\(cacheRead)/\(cacheWrite) out=\(output)"
    }

    /// Under 1,000 as is; 1,000 to 9,999 as `1.2k` (`.0` dropped); up to a million as whole `k`; then `1.2M`.
    /// Rounds down, so a figure never reads higher than it is (and 9,999 is not `10.0k`).
    static func short(_ n: Int) -> String {
        func tenths(_ n: Int, per unit: Int) -> String {
            let t = n / (unit / 10)
            return t % 10 == 0 ? "\(t / 10)" : "\(t / 10).\(t % 10)"
        }
        switch n {
        case ..<1_000: return "\(n)"
        case ..<10_000: return tenths(n, per: 1_000) + "k"
        case ..<1_000_000: return "\(n / 1_000)k"
        default: return tenths(n, per: 1_000_000) + "M"
        }
    }
}
