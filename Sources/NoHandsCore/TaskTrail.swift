import Foundation

/// One step of a multi-step task, as the corner panel lists it.
public struct TaskStepRecord: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, done, failed(String) }
    public let number: Int
    public let intent: String
    public var state: State

    public init(number: Int, intent: String, state: State) {
        self.number = number
        self.intent = intent
        self.state = state
    }
}

/// The steps a task has taken so far. Rides on the prompt's board row; the corner panel reads it.
public struct TaskTrail: Equatable, Sendable {
    /// Why a task that did not finish stopped. Carried as data so nothing parses `status.text`.
    public enum Ending: Equatable, Sendable { case stepCap, stuck }

    public let maxSteps: Int
    public private(set) var steps: [TaskStepRecord] = []
    public var ending: Ending?

    public init(maxSteps: Int) {
        self.maxSteps = maxSteps
    }

    /// Appends a running step.
    public mutating func begin(number: Int, intent: String) {
        steps.append(TaskStepRecord(number: number, intent: intent, state: .running))
    }

    /// Running becomes done, or failed with the reason. An unknown number changes nothing.
    public mutating func end(number: Int, failure: String?) {
        guard let i = steps.firstIndex(where: { $0.number == number }) else { return }
        steps[i].state = failure.map { .failed($0) } ?? .done
    }
}

/// What the corner panel shows: the phrase, the step trail, a progress bar and a closing line.
public struct TaskPanelContent: Equatable, Sendable {
    public enum Mark: Equatable, Sendable { case done, current, failed, stopped }
    public struct Line: Equatable, Sendable {
        public let text: String
        public let mark: Mark
    }
    public struct Progress: Equatable, Sendable {
        public let label: String
        public let fraction: Double
    }

    public let phrase: String
    /// Older steps not listed ("+ 4 earlier steps").
    public let earlierSteps: Int
    /// At most the newest `TaskPanelText.maxLines` steps, oldest first.
    public let lines: [Line]
    public let progress: Progress?
    public let footer: StatusLine?
}

/// Picks the board row the corner panel shows and builds its content. Pure; the overlay only draws it.
public enum TaskPanelText {
    public static let maxLines = 8
    static let thinking = "Working out the next step\u{2026}"

    /// nil when no row should show: the panel hides. `rows` is the board's visible rows.
    public static func content(rows: [PromptRow]) -> TaskPanelContent? {
        guard let row = chosenRow(rows) else { return nil }
        return build(row)
    }

    // MARK: Row choice

    /// First match wins; the newest row within a kind. A task's outcome holds against words that are only being
    /// spoken or waiting, but not against a task that is running or a phrase already heard.
    private static func chosenRow(_ rows: [PromptRow]) -> PromptRow? {
        func newest(_ matching: (PromptStatus) -> Bool) -> PromptRow? {
            rows.filter { matching($0.status) }.max(by: older)
        }
        let outcome = newest {
            switch $0 {
            case .done, .failed, .stopped: true
            default: false
            }
        }
        if let r = newest({ if case .running = $0 { true } else { false } }) { return r }
        if let r = newest({ $0 == .heard }) { return r }
        if let r = outcome, r.trail != nil { return r }
        if let r = newest({ $0 == .listening }) { return r }
        if let r = newest({ $0 == .held }) { return r }
        if let r = outcome { return r }
        return newest { $0.isFinal }
    }

    /// True when `a` is older than `b` (ties go to the later prompt).
    private static func older(_ a: PromptRow, _ b: PromptRow) -> Bool {
        a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.id < b.id
    }

    // MARK: Content

    private static func build(_ row: PromptRow) -> TaskPanelContent {
        let status = StatusLine(text: row.status.text, tone: row.status.tone)
        guard let trail = row.trail else {
            return TaskPanelContent(phrase: row.text, earlierSteps: 0, lines: [], progress: nil, footer: status)
        }
        let steps = trail.steps
        let final = row.status.isFinal
        let shown = steps.suffix(maxLines)
        let lines = shown.map { line($0, final: final, status: row.status) }

        var progress: TaskPanelContent.Progress?
        if let last = steps.last {
            progress = bar(last.number, of: trail.maxSteps)
        }

        let footer: StatusLine?
        switch row.status {
        case .failed:
            switch trail.ending {
            case .stepCap:
                progress = bar(trail.maxSteps, of: trail.maxSteps)
                footer = StatusLine(text: "Hit the \(trail.maxSteps)-step limit \u{00B7} try a smaller request", tone: .bad)
            case .stuck:
                footer = StatusLine(text: "\(status.text) \u{00B7} say it another way", tone: .bad)
            case nil:
                footer = StatusLine(text: "\(status.text) \u{00B7} try again", tone: .bad)
            }
        case _ where final:
            footer = status
        default:
            // Still going: between steps the model is thinking, which is the slow part.
            footer = steps.last?.state == .running ? nil : StatusLine(text: thinking, tone: .active)
        }
        return TaskPanelContent(
            phrase: row.text, earlierSteps: steps.count - shown.count, lines: lines, progress: progress,
            footer: footer)
    }

    private static func bar(_ n: Int, of m: Int) -> TaskPanelContent.Progress {
        TaskPanelContent.Progress(label: "step \(n) of \(m)", fraction: min(1, Double(n) / Double(max(1, m))))
    }

    private static func line(_ step: TaskStepRecord, final: Bool, status: PromptStatus) -> TaskPanelContent.Line {
        let name = OverlayMath.hudText(step.intent, maxChars: 80) ?? "step \(step.number)"
        switch step.state {
        case .done:
            return .init(text: name, mark: .done)
        case .failed(let why):
            // Cut the whole line, not the intent alone, so a long failure cannot widen it.
            let intent = OverlayMath.hudText(step.intent, maxChars: .max) ?? "step \(step.number)"
            return .init(text: OverlayMath.hudText("\(intent) \u{00B7} \(why)") ?? name, mark: .failed)
        case .running:
            guard final else { return .init(text: name, mark: .current) }
            // The task ended with this step still in flight: how it ended decides how it shows.
            switch status {
            case .done: return .init(text: name, mark: .done)
            case .stopped: return .init(text: name, mark: .stopped)
            default: return .init(text: name, mark: .failed)
            }
        }
    }
}
