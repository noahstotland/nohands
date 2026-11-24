import Foundation

/// One step of a multi-step task, as the corner panel lists it.
public struct TaskStepRecord: Equatable, Sendable {
    public enum State: Equatable, Sendable { case running, done, failed(String) }
    public let number: Int
    public let intent: String
    public var state: State
    /// The step's actions (after the typed-address rewrite), so the panel can name what is being done.
    public let actions: [Action]
    /// When the step began, and how long it took once it ended. Feed the command log.
    public let startedAt: Date?
    public var duration: Duration?

    public init(number: Int, intent: String, state: State, actions: [Action] = [],
                startedAt: Date? = nil, duration: Duration? = nil) {
        self.number = number
        self.intent = intent
        self.state = state
        self.actions = actions
        self.startedAt = startedAt
        self.duration = duration
    }
}

/// What a running task is doing right now. Set by the runner, shown as one line on the corner panel.
public enum TaskPhase: Equatable, Sendable { case reading, planning, thinking, acting }

/// The steps a task has taken so far. Rides on the prompt's board row; the corner panel reads it.
public struct TaskTrail: Equatable, Sendable {
    /// Why a task that did not finish stopped. Carried as data so nothing parses `status.text`.
    public enum Ending: Equatable, Sendable { case stepCap, stuck }

    public let maxSteps: Int
    public private(set) var steps: [TaskStepRecord] = []
    public var ending: Ending?
    /// Nil when the task is not running.
    public var phase: TaskPhase?
    /// The rows are choices to pick from (a file list), not steps taken: no step count, and the prompt is the footer.
    public let choices: Bool

    public init(maxSteps: Int, choices: Bool = false) {
        self.maxSteps = maxSteps
        self.choices = choices
    }

    /// Appends a running step.
    public mutating func begin(number: Int, intent: String, actions: [Action] = [], at date: Date = Date()) {
        steps.append(TaskStepRecord(number: number, intent: intent, state: .running, actions: actions, startedAt: date))
    }

    /// Running becomes done, or failed with the reason, and the step's duration is set. An unknown number, or a step
    /// that already ended, changes nothing.
    public mutating func end(number: Int, failure: String?, at date: Date = Date()) {
        guard let i = steps.firstIndex(where: { $0.number == number }), steps[i].duration == nil else { return }
        steps[i].state = failure.map { .failed($0) } ?? .done
        steps[i].duration = steps[i].startedAt.map { .seconds(max(0, date.timeIntervalSince($0))) }
    }
}

/// What the corner panel shows: the phrase, the step trail, the step number and a closing line.
public struct TaskPanelContent: Equatable, Sendable {
    public enum Mark: Equatable, Sendable { case done, current, failed, stopped }
    public struct Line: Equatable, Sendable {
        public let text: String
        public let mark: Mark
    }
    public struct Progress: Equatable, Sendable {
        public let label: String
    }

    public let phrase: String
    /// Older steps not listed ("+ 4 earlier steps").
    public let earlierSteps: Int
    /// At most the newest `TaskPanelText.maxLines` steps, oldest first.
    public let lines: [Line]
    public let progress: Progress?
    public let footer: StatusLine?
    /// True while the task is in flight with a phase: the panel shows its spinner and the footer is the phase line.
    public let busy: Bool
}

/// Picks the board row the corner panel shows and builds its content. Pure; the overlay only draws it.
public enum TaskPanelText {
    public static let maxLines = 8

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
        // A spoken stop clears the panel at once, and stays clear however long each row lingers: the stopped task, the
        // stop phrase's own row and the held job a stop discards (both `.stopped`) never get a panel.
        let outcome = newest {
            switch $0 {
            case .done, .failed: true
            default: false
            }
        }
        if let r = newest({ if case .running = $0 { true } else { false } }) { return r }
        if let r = newest({ $0 == .heard }) { return r }
        if let r = outcome, r.trail != nil { return r }
        if let r = newest({ $0 == .listening }) { return r }
        if let r = newest({ $0 == .held }) { return r }
        if let r = outcome { return r }
        return newest { $0.isFinal && !isStopped($0) }
    }

    private static func isStopped(_ s: PromptStatus) -> Bool {
        if case .stopped = s { true } else { false }
    }

    /// True when `a` is older than `b` (ties go to the later prompt).
    private static func older(_ a: PromptRow, _ b: PromptRow) -> Bool {
        a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.id < b.id
    }

    // MARK: Content

    private static func build(_ row: PromptRow) -> TaskPanelContent {
        let status = StatusLine(text: row.status.text, tone: row.status.tone)
        guard let trail = row.trail else {
            return TaskPanelContent(phrase: row.text, earlierSteps: 0, lines: [], progress: nil, footer: status, busy: false)
        }
        let steps = trail.steps
        let final = row.status.isFinal
        let shown = steps.suffix(maxLines)
        let lines = shown.map { line($0, final: final, status: row.status) }

        var progress: TaskPanelContent.Progress?
        if let last = steps.last, !trail.choices {
            progress = stepLabel(last.number)
        }

        let footer: StatusLine?
        let busy = !final && trail.phase != nil
        switch row.status {
        case .failed:
            switch trail.ending {
            case .stepCap:
                footer = StatusLine(text: "Hit the \(trail.maxSteps)-step limit \u{00B7} try a smaller request", tone: .bad)
            case .stuck:
                footer = StatusLine(text: "\(status.text) \u{00B7} say it another way", tone: .bad)
            case nil:
                footer = StatusLine(text: "\(status.text) \u{00B7} try again", tone: .bad)
            }
        case _ where final:
            footer = status
        default:
            footer = trail.choices ? status : phaseLine(trail).map { StatusLine(text: $0, tone: .active) }
        }
        return TaskPanelContent(
            phrase: row.text, earlierSteps: steps.count - shown.count, lines: lines, progress: progress,
            footer: footer, busy: busy)
    }

    /// The one line that says what a running task is doing, in plain words. Payload-free: no typed text, URLs or
    /// search words. Nil when the trail has no phase.
    public static func phaseLine(_ trail: TaskTrail) -> String? {
        guard let phase = trail.phase else { return nil }
        let last = trail.steps.last
        switch phase {
        case .reading:
            return last == nil ? "Reading \u{00B7} looking at the screen" : "Reading \u{00B7} checking what changed"
        case .planning:
            return "Thinking \u{00B7} planning the steps"
        case .thinking:
            if last == nil { return "Thinking \u{00B7} working out the first step" }
            if case .failed? = last?.state { return "Thinking \u{00B7} finding another way" }
            return "Thinking \u{00B7} picking the next step"
        case .acting:
            guard let step = last else { return "Acting" }
            let doing = step.actions.first { $0 != .look && !isWait($0) }
            return "Acting \u{00B7} " + (doing.map(ActionSummary.verb) ?? "step \(step.number)")
        }
    }

    private static func isWait(_ a: Action) -> Bool {
        switch a {
        case .wait, .waitFor: true
        default: false
        }
    }

    /// The step number alone: the step limit is not how many steps the task needs, and nobody knows that in advance.
    private static func stepLabel(_ n: Int) -> TaskPanelContent.Progress {
        TaskPanelContent.Progress(label: "step \(n)")
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
