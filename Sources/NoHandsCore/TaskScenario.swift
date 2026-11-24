import Foundation

/// Where a scenario begins: an app brought to the front, or a page opened in the default browser.
public enum ScenarioStart: Equatable, Sendable { case app(String), url(URL) }

/// One screen check, judged from a fresh observation and never from what the model claims.
public enum ScenarioCheck: Equatable, Sendable {
    case windowTitleContains(String), urlMatches(String), elementVisible(String), elementAbsent(String), mediaPlaying

    public func holds(in o: ScreenObservation) -> Bool {
        func has(_ text: String) -> Bool { o.elements.contains { $0.title.range(of: text, options: .caseInsensitive) != nil } }
        switch self {
        case .windowTitleContains(let t): return o.windowTitle.range(of: t, options: .caseInsensitive) != nil
        case .urlMatches(let p):
            guard let url = o.url, let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive) else { return false }
            return re.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        case .elementVisible(let t): return has(t)
        // An empty list is a page that was not read, not a page without the element. The list is the observer's
        // capped one (300 from agent-desktop, 200 from the native walk), so an element past the cap reads as absent;
        // the command also looks for the Pause control to click in that list.

        case .elementAbsent(let t): return !o.elements.isEmpty && !has(t)
        case .mediaPlaying: return o.media == .playing
        }
    }

    /// For failure lines, e.g. `urlMatches youtube\.com/watch`.
    public var label: String {
        switch self {
        case .windowTitleContains(let t): "windowTitleContains \(t)"
        case .urlMatches(let t): "urlMatches \(t)"
        case .elementVisible(let t): "elementVisible \(t)"
        case .elementAbsent(let t): "elementAbsent \(t)"
        case .mediaPlaying: "mediaPlaying"
        }
    }
}

public struct TaskScenario: Equatable, Sendable {
    public var name: String
    public var goal: String
    public var start: ScenarioStart
    public var ready: [ScenarioCheck]
    public var success: [ScenarioCheck]
    public var maxSteps: Int

    public init(name: String, goal: String, start: ScenarioStart, ready: [ScenarioCheck], success: [ScenarioCheck], maxSteps: Int) {
        self.name = name; self.goal = goal; self.start = start; self.ready = ready; self.success = success; self.maxSteps = maxSteps
    }

    /// The default start state: the front app's name contains the given one (a substring, as the app lookup is
    /// fuzzy too) and has a window, or the page has the start URL's host
    /// and path (a leading `www.` and a trailing `/` ignored).
    public static func startHolds(_ s: ScenarioStart, in o: ScreenObservation) -> Bool {
        switch s {
        case .app(let name): return o.app.range(of: name, options: .caseInsensitive) != nil && !o.windowTitle.isEmpty
        case .url(let u):
            guard let seen = o.url.flatMap(URL.init(string:)), let want = pageKey(u) else { return false }
            return pageKey(seen) == want
        }
    }

    private static func pageKey(_ u: URL) -> String? {
        guard var host = u.host?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = u.path
        while path.hasSuffix("/") { path.removeLast() }
        return host + (path.isEmpty ? "/" : path)
    }

    public static func verdict(end: TaskEnd, checksHold: Bool) -> ScenarioVerdict {
        switch (end, checksHold) {
        case (.stopped, _): .stopped
        case (.done, true): .pass
        case (.done, false): .falseDone
        case (_, true): .unclaimed
        case (_, false): .fail
        }
    }
}

/// How the task loop ended. `ignored` exits 0 in the CLI but is never a success.
public enum TaskEnd: Equatable, Sendable { case done, stuck, failed, ignored, stopped }

public enum ScenarioVerdict: String, CaseIterable, Sendable {
    case pass, falseDone = "false-done", unclaimed, fail, stopped, startFailed = "start-failed", notRun = "not-run"
}

public struct ScenarioFileError: Error, LocalizedError, Equatable, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

public enum ScenarioFile {
    private enum Value: Decodable {
        case string(String), bool(Bool)
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if let b = try? c.decode(Bool.self) { self = .bool(b) } else { self = .string(try c.decode(String.self)) }
        }
    }
    private struct RawStart: Decodable { var app: String?; var url: String? }
    private struct Raw: Decodable {
        var name: String?; var goal: String?; var start: RawStart?
        var ready: [[String: Value]]?; var success: [[String: Value]]?; var maxSteps: Int?
    }

    /// Decodes and validates a scenario file. `run` replaces `{run}` in every goal and check text. Nothing is
    /// returned unless every scenario is valid.
    public static func load(_ data: Data, run: Int) throws -> [TaskScenario] {
        let raws: [Raw]
        do { raws = try JSONDecoder().decode([Raw].self, from: data) }
        catch { throw ScenarioFileError(message: "scenario file is not valid JSON for a scenario list: \(error.localizedDescription)") }
        var seen = Set<String>()
        return try raws.enumerated().map { i, raw in
            let name = raw.name ?? "scenario #\(i + 1)"
            func bad(_ why: String) -> ScenarioFileError { ScenarioFileError(message: "\(name): \(why)") }
            func sub(_ s: String) -> String { s.replacingOccurrences(of: "{run}", with: String(run)) }
            guard let n = raw.name, !n.isEmpty else { throw bad("missing name") }
            guard seen.insert(n).inserted else { throw bad("duplicate name") }
            guard let goal = raw.goal, !goal.trimmingCharacters(in: .whitespaces).isEmpty else { throw bad("missing goal") }
            guard let rawStart = raw.start, (rawStart.app == nil) != (rawStart.url == nil) else {
                throw bad("start needs exactly one of app or url")
            }
            let start: ScenarioStart
            if rawStart.app?.isEmpty == true { throw bad("start app is empty") }
            if let app = rawStart.app { start = .app(app) }
            else if let s = rawStart.url, let u = URL(string: s), ["http", "https"].contains(u.scheme?.lowercased()), u.host != nil { start = .url(u) }
            else { throw bad("start url must be http or https") }
            guard let steps = raw.maxSteps, (1...30).contains(steps) else { throw bad("maxSteps must be 1 to 30") }

            func checks(_ list: [[String: Value]], _ field: String) throws -> [ScenarioCheck] {
                let out: [ScenarioCheck] = try list.map { dict in
                    guard dict.count == 1, let (key, value) = dict.first else { throw bad("each \(field) check needs exactly one key") }
                    if key == "mediaPlaying" {
                        guard case .bool(true) = value else { throw bad("mediaPlaying must be true") }
                        return .mediaPlaying
                    }
                    guard case .string(let raw) = value, !raw.isEmpty else { throw bad("\(key) needs non-empty text") }
                    let text = sub(raw)
                    switch key {
                    case "windowTitleContains": return .windowTitleContains(text)
                    case "urlMatches":
                        guard (try? NSRegularExpression(pattern: text)) != nil else { throw bad("urlMatches is not a valid regular expression") }
                        return .urlMatches(text)
                    case "elementVisible": return .elementVisible(text)
                    case "elementAbsent": return .elementAbsent(text)
                    default: throw bad("unknown check \(key)")
                    }
                }
                let hasAbsent = out.contains { if case .elementAbsent = $0 { true } else { false } }
                let hasVisible = out.contains { if case .elementVisible = $0 { true } else { false } }
                if hasAbsent && !hasVisible { throw bad("elementAbsent in \(field) needs an elementVisible beside it") }
                return out
            }
            let success = try checks(raw.success ?? [], "success")
            guard !success.isEmpty else { throw bad("success needs at least one check") }
            return TaskScenario(name: n, goal: sub(goal), start: start, ready: try checks(raw.ready ?? [], "ready"),
                                success: success, maxSteps: steps)
        }
    }
}

public struct ScenarioResult: Sendable {
    public var name: String
    public var verdict: ScenarioVerdict
    public var steps: Int
    public var seconds: Double
    public init(name: String, verdict: ScenarioVerdict, steps: Int, seconds: Double) {
        self.name = name; self.verdict = verdict; self.steps = steps; self.seconds = seconds
    }
}

public enum ScenarioReport {
    /// A markdown table. Cells come from the file and the screen, so control characters become spaces and `|` is escaped.
    public static func table(_ results: [ScenarioResult]) -> String {
        func cell(_ s: String) -> String {
            let clean = String(s.unicodeScalars.map { u -> Character in
                let c = u.properties.generalCategory
                return c == .control || c == .lineSeparator || c == .paragraphSeparator ? " " : Character(u)
            })
            return clean.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "|", with: "\\|")
        }
        let rows = results.map { "| \(cell($0.name)) | \($0.verdict.rawValue) | \($0.steps) | \(String(format: "%.1f", $0.seconds)) s |" }
        return (["| scenario | verdict | steps | time |", "|---|---|---|---|"] + rows).joined(separator: "\n")
    }

    /// `2 of 6 pass; false-done 1, fail 3`: the verdicts that are not `pass`, when there are any.
    public static func summary(_ results: [ScenarioResult]) -> String {
        let others = ScenarioVerdict.allCases.filter { $0 != .pass }.compactMap { v -> String? in
            let n = results.filter { $0.verdict == v }.count
            return n == 0 ? nil : "\(v.rawValue) \(n)"
        }
        let head = "\(results.filter { $0.verdict == .pass }.count) of \(results.count) pass"
        return others.isEmpty ? head : head + "; " + others.joined(separator: ", ")
    }
}
