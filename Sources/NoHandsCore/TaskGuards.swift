import Foundation

/// Phrases that abort a running task.
public enum StopWords {
    private static let phrases: Set<String> = [
        "stop", "stop it", "stop that", "cancel", "cancel that",
        "never mind", "nevermind", "abort", "halt", "stop the task",
    ]
    /// Words that make a phrase a stop on their own.
    private static let stopTokens: Set<String> = ["stop", "cancel", "nevermind", "abort", "halt"]
    /// Words that may surround stop words without changing the meaning ("um stop", "no stop", "stop stop it").
    private static let fillerTokens: Set<String> = [
        "um", "uh", "er", "oh", "no", "wait", "please", "ok", "okay", "now", "it", "that", "the", "task",
    ]

    /// An exact stop phrase, or a phrase made only of stop words and fillers with at least one stop word
    /// ("Stop, stop!", "no stop", "um stop"). "stop dictating" or "stop the music" are not stops.
    public static func isStop(_ transcript: String) -> Bool {
        let phrase = CommandGrammar.normalize(transcript).joined(separator: " ")
        if phrases.contains(phrase) { return true }
        let tokens = phrase.replacingOccurrences(of: "never mind", with: "nevermind").split(separator: " ").map(String.init)
        return tokens.contains(where: stopTokens.contains)
            && tokens.allSatisfy { stopTokens.contains($0) || fillerTokens.contains($0) }
    }
}

/// Ctrl-C while a task runs: the first one stops the task (like "stop"), a second one exits at once.
public struct InterruptPolicy: Sendable {
    public enum Response: Equatable, Sendable { case stopTask, exitNow }
    /// Conventional status for a process ended by SIGINT.
    public static let exitStatus: Int32 = 130
    private var count = 0

    public init() {}

    public mutating func interrupt() -> Response {
        count += 1
        return count == 1 ? .stopTask : .exitNow
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
    /// `media` is compared too: media without a control (`playing` with none found) comes from Mac-wide audio.
    public static func same(_ a: ScreenObservation, _ b: ScreenObservation) -> Bool {
        sameFrame(a, b) && signature(a.elements) == signature(b.elements)
    }

    /// Same screen state apart from element values: the same app, window, URL, surface, media and the same
    /// elements (by role, title and states). A ticking clock or counter differs only this way.
    static func sameExceptValues(_ a: ScreenObservation, _ b: ScreenObservation) -> Bool {
        sameFrame(a, b) && identities(a.elements) == identities(b.elements)
    }

    /// The element identities whose values (compared as a group) differ between two readings.
    static func changedValues(_ a: ScreenObservation, _ b: ScreenObservation) -> Set<String> {
        let (x, y) = (valueGroups(a.elements), valueGroups(b.elements))
        return Set(x.keys).union(y.keys).filter { x[$0] != y[$0] }
    }

    private static func sameFrame(_ a: ScreenObservation, _ b: ScreenObservation) -> Bool {
        a.app == b.app && a.windowTitle == b.windowTitle && a.url == b.url && a.surface == b.surface && a.media == b.media
    }

    /// Numbers (and refs) are left out: a re-snapshot renumbers the same screen.
    private static func signature(_ elements: [ObservedElement]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for e in elements { counts[identity(e) + "\u{1F}" + (e.value ?? ""), default: 0] += 1 }
        return counts
    }

    private static func identity(_ e: ObservedElement) -> String {
        e.role + "\u{1F}" + e.title + "\u{1F}" + e.states.joined(separator: ",")
    }

    private static func identities(_ elements: [ObservedElement]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for e in elements { counts[identity(e), default: 0] += 1 }
        return counts
    }

    private static func valueGroups(_ elements: [ObservedElement]) -> [String: [String]] {
        var groups: [String: [String]] = [:]
        for e in elements { groups[identity(e), default: []].append(e.value ?? "") }
        return groups.mapValues { $0.sorted() }
    }
}
