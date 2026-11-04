import Foundation

/// Phrases that abort a running task.
public enum StopWords {
    private static let phrases: Set<String> = [
        "stop", "stop it", "stop that", "cancel", "cancel that",
        "never mind", "nevermind", "abort", "halt", "stop the task",
    ]

    public static func isStop(_ transcript: String) -> Bool {
        phrases.contains(CommandGrammar.normalize(transcript).joined(separator: " "))
    }
}

/// Detects a task loop proposing the same actions over and over.
public struct RepeatDetector: Sendable {
    public let limit: Int
    private var last: [Action] = []
    private var streak = 0

    public init(limit: Int = 3) { self.limit = max(1, limit) }

    /// True when the last `limit` recorded lists are identical and non-empty. An empty list resets the streak.
    public mutating func record(_ actions: [Action]) -> Bool {
        guard !actions.isEmpty else { last = []; streak = 0; return false }
        streak = (actions == last) ? streak + 1 : 1
        last = actions
        return streak >= limit
    }
}

/// Whether two observations show the same screen state.
public enum Settle {
    public static func same(_ a: ScreenObservation, _ b: ScreenObservation) -> Bool {
        a.app == b.app && a.windowTitle == b.windowTitle && a.url == b.url
            && signature(a.elements) == signature(b.elements)
    }

    private static func signature(_ elements: [ObservedElement]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for e in elements { counts[e.role + "\u{1F}" + e.title, default: 0] += 1 }
        return counts
    }
}
