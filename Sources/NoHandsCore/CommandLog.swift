import Foundation

/// One command the user spoke, what ran for it and how it ended. Private and local: it holds spoken phrases and
/// typed text, so it is only ever written to the owner-only log file and shown in the View Logs window.
public struct CommandLogEntry: Codable, Equatable, Sendable {
    public enum Resolver: String, Codable, Sendable { case grammar, claude, localModel, none }
    public enum Outcome: Codable, Equatable, Sendable { case done, failed(String), stopped, ignored(String) }

    public struct Step: Codable, Equatable, Sendable {
        public let number: Int
        /// The step's intent, or the detailed action summary for a grammar command.
        public let action: String
        public let result: Outcome
        public let startedAt: Date?
        public let durationMs: Int?

        public init(number: Int, action: String, result: Outcome, startedAt: Date? = nil, durationMs: Int? = nil) {
            self.number = number; self.action = action; self.result = result
            self.startedAt = startedAt; self.durationMs = durationMs
        }
    }

    /// The Claude calls a command made, summed.
    public struct Usage: Codable, Equatable, Sendable {
        public let calls: Int
        public let inputTokens: Int
        public let cacheReadTokens: Int
        public let cacheWriteTokens: Int

        public init(calls: Int, inputTokens: Int, cacheReadTokens: Int, cacheWriteTokens: Int) {
            self.calls = calls; self.inputTokens = inputTokens
            self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens
        }

        /// nil for an empty list (no Claude call was made).
        public static func sum(_ calls: [ClaudeUsage]) -> Usage? {
            guard !calls.isEmpty else { return nil }
            return Usage(calls: calls.count, inputTokens: calls.reduce(0) { $0.saturatingAdd($1.inputTokens) },
                         cacheReadTokens: calls.reduce(0) { $0.saturatingAdd($1.cacheReadTokens) },
                         cacheWriteTokens: calls.reduce(0) { $0.saturatingAdd($1.cacheWriteTokens) })
        }
    }

    public let id: UUID
    public let date: Date
    public let phrase: String
    public let resolver: Resolver
    public let steps: [Step]
    public let outcome: Outcome
    public let durationMs: Int
    /// nil when no Claude call was made.
    public let usage: Usage?

    public init(id: UUID = UUID(), date: Date, phrase: String, resolver: Resolver, steps: [Step], outcome: Outcome,
                durationMs: Int, usage: Usage? = nil) {
        self.id = id; self.date = date; self.phrase = phrase; self.resolver = resolver
        self.steps = steps; self.outcome = outcome; self.durationMs = durationMs; self.usage = usage
    }

    /// A model task: one step per trail step, in the order they ran. A step still running when the task ended takes
    /// the task's ending, the same rule the corner panel uses, and runs until `endedAt` (default: `date` plus
    /// `durationMs`).
    public static func fromTrail(_ trail: TaskTrail, id: UUID = UUID(), date: Date, phrase: String, resolver: Resolver,
                                 outcome: Outcome, durationMs: Int, usage: Usage?, endedAt: Date? = nil) -> CommandLogEntry {
        let end = endedAt ?? date.addingTimeInterval(Double(durationMs) / 1000)
        let steps = trail.steps.map { step -> Step in
            let result: Outcome
            switch step.state {
            case .done: result = .done
            case .failed(let why): result = .failed(why)
            case .running:
                switch outcome {
                case .done: result = .done
                case .stopped: result = .stopped
                case .failed(let why): result = .failed(why)
                case .ignored: result = .failed("ended")
                }
            }
            let stepMs = step.duration.map(Self.milliseconds)
                ?? (step.state == .running ? step.startedAt.map { max(0, Int(end.timeIntervalSince($0) * 1000)) } : nil)
            return Step(number: step.number, action: step.intent, result: result, startedAt: step.startedAt,
                        durationMs: stepMs)
        }
        return CommandLogEntry(id: id, date: date, phrase: phrase, resolver: resolver, steps: steps, outcome: outcome,
                               durationMs: durationMs, usage: usage)
    }

    /// A grammar command: one step (`action` is the detailed action summary) that is done or failed with the reason.
    public static func grammar(id: UUID = UUID(), date: Date, phrase: String, action: String, failure: String?,
                               durationMs: Int) -> CommandLogEntry {
        let result: Outcome = failure.map { .failed($0) } ?? .done
        let step = Step(number: 1, action: action, result: result, startedAt: date, durationMs: durationMs)
        return CommandLogEntry(id: id, date: date, phrase: phrase, resolver: .grammar, steps: [step], outcome: result,
                               durationMs: durationMs)
    }

    public static func milliseconds(_ d: Duration) -> Int {
        let c = d.components
        return Int(c.seconds) * 1000 + Int(c.attoseconds / 1_000_000_000_000_000)
    }
}

/// The newest 50 commands, newest first.
public struct CommandLog: Equatable, Sendable {
    public static let limit = 50

    public private(set) var entries: [CommandLogEntry]

    public init(entries: [CommandLogEntry] = []) {
        self.entries = Array(entries.prefix(Self.limit))
    }

    /// Inserts at the front and drops the oldest past `limit`.
    public mutating func append(_ entry: CommandLogEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    private struct File: Codable { let entries: [CommandLogEntry] }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public func encoded() throws -> Data {
        try Self.encoder.encode(File(entries: entries))
    }

    /// A missing, empty or corrupt file, a wrong top-level shape, or any entry that fails to decode gives an empty
    /// log: the whole file or nothing. A valid file with more than `limit` entries keeps the newest.
    public static func decode(_ data: Data?) -> CommandLog {
        guard let data, !data.isEmpty else { return CommandLog() }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let file = try? d.decode(File.self, from: data) else { return CommandLog() }
        return CommandLog(entries: file.entries)
    }
}

/// The wording of the Recent commands submenu and the View Logs window, in one place.
public enum CommandLogText {
    /// `<phrase> · <outcome>`, short enough for a menu.
    public static func menuLine(_ entry: CommandLogEntry) -> String {
        let phrase = OverlayMath.hudText(entry.phrase, maxChars: 44) ?? "(no words)"
        return "\(phrase) \u{00B7} \(outcomeWord(entry.outcome))"
    }

    /// The time, phrase and outcome for one row of the window's list.
    public static func listLine(_ entry: CommandLogEntry, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        "\(clock(entry.date, locale, timeZone)) \u{00B7} \(menuLine(entry))"
    }

    /// Everything about one command: when, what was said, who resolved it, each step with result and timing, how it
    /// ended, and the Claude calls and tokens.
    public static func detail(_ entry: CommandLogEntry, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var lines = ["\(clock(entry.date, locale, timeZone)) \u{00B7} \u{201C}\(entry.phrase)\u{201D} \u{00B7} \(resolverName(entry.resolver))"]
        for step in entry.steps {
            var parts = ["\(step.number). \(collapsed(step.action))", resultText(step.result, lower: true)]
            if let at = step.startedAt { parts.append(clock(at, locale, timeZone)) }
            if let ms = step.durationMs { parts.append(seconds(ms)) }
            lines.append(parts.joined(separator: " \u{00B7} "))
        }
        lines.append("\(resultText(entry.outcome, lower: false)) \u{00B7} \(seconds(entry.durationMs))")
        if let u = entry.usage {
            func n(_ v: Int) -> String { v.formatted(IntegerFormatStyle<Int>.number.locale(locale)) }
            lines.append("Claude: \(u.calls) \(u.calls == 1 ? "call" : "calls") \u{00B7} \(n(u.inputTokens)) in \u{00B7} "
                         + "\(n(u.cacheReadTokens)) cache read \u{00B7} \(n(u.cacheWriteTokens)) cache write")
        }
        return lines.joined(separator: "\n")
    }

    static func resolverName(_ r: CommandLogEntry.Resolver) -> String {
        switch r {
        case .grammar: "Grammar"
        case .claude: "Claude"
        case .localModel: "Local model"
        case .none: "No model"
        }
    }

    private static func outcomeWord(_ o: CommandLogEntry.Outcome) -> String {
        switch o {
        case .done: "done"
        case .failed: "failed"
        case .stopped: "stopped"
        case .ignored: "ignored"
        }
    }

    /// "done", "failed: reason", "stopped", "ignored: hint"; `lower: false` capitalises the first word.
    private static func resultText(_ o: CommandLogEntry.Outcome, lower: Bool) -> String {
        let text: String
        switch o {
        case .done, .stopped: text = outcomeWord(o)
        case .failed(let why), .ignored(let why):
            let reason = collapsed(why)
            text = reason.isEmpty ? outcomeWord(o) : "\(outcomeWord(o)): \(reason)"
        }
        return lower ? text : text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func collapsed(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
    }

    private static func seconds(_ ms: Int) -> String { String(format: "%.1f s", Double(ms) / 1000) }

    private static func clock(_ date: Date, _ locale: Locale, _ timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: locale, timeZone: timeZone))
    }
}
