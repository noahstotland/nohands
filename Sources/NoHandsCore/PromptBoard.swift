import Foundation

/// How far a spoken prompt has got. Each prompt is one row on the board at the top of the screen; the status is
/// its right-hand cell and colour.
public enum PromptStatus: Equatable, Sendable {
    /// Still being spoken: the merge window holds the words heard so far.
    case listening
    /// Transcribed and routed; about to run.
    case heard
    /// Working. The detail is the current step ("step 2 · open the menu") or what the last step failed with.
    case running(String)
    /// Spoken while a task ran; runs once that task ends.
    case held
    /// Finished as asked. The detail is the finish line ("done · open the menu (2 steps)").
    case done(String)
    /// Could not be carried out: an action failed, the model gave up, or the resolver failed.
    case failed(String)
    /// A stop phrase or a pause ended it.
    case stopped(String)
    /// Never ran: arrived while busy, waited too long, or was discarded by a stop.
    case dropped(String)
    /// Nothing to do: not a computer action, or no resolver to ask.
    case ignored(String)

    public enum Tone: Equatable, Sendable { case active, waiting, good, bad, muted }

    public var tone: Tone {
        switch self {
        case .listening, .heard, .running: .active
        case .held: .waiting
        case .done: .good
        case .failed, .dropped: .bad
        case .stopped, .ignored: .muted
        }
    }

    /// A final status never changes again; its row leaves the board after a short while.
    public var isFinal: Bool {
        switch self {
        case .listening, .heard, .running, .held: false
        case .done, .failed, .stopped, .dropped, .ignored: true
        }
    }

    /// The status cell: the detail when there is one, else the plain word.
    public var text: String {
        switch self {
        case .listening: "listening…"
        case .heard: "heard"
        case .held: "held · runs after this task (say stop to cancel)"
        case .running(let d): d.isEmpty ? "running…" : d
        case .done(let d): d.isEmpty ? "done" : d
        case .failed(let d): d.isEmpty ? "failed" : d
        case .stopped(let d): d.isEmpty ? "stopped" : d
        case .dropped(let d): d.isEmpty ? "dropped" : d
        case .ignored(let d): d.isEmpty ? "ignored" : d
        }
    }
}

/// One prompt on the board.
public struct PromptRow: Equatable, Sendable {
    public var id: Int
    public var text: String
    public var status: PromptStatus
    public var updatedAt: ContinuousClock.Instant

    public init(id: Int, text: String, status: PromptStatus, updatedAt: ContinuousClock.Instant) {
        self.id = id
        self.text = text
        self.status = status
        self.updatedAt = updatedAt
    }
}

/// A transient line that is not a prompt (loading, listening, an error).
public struct PromptNotice: Equatable, Sendable {
    public var text: String
    public var until: ContinuousClock.Instant
}

/// The rows shown at the top of the screen: the recent prompts, oldest first, plus at most one notice. Pure
/// bookkeeping; the overlay draws `visibleRows` and asks `nextChange` when to redraw.
public struct PromptBoard: Equatable, Sendable {
    public private(set) var rows: [PromptRow] = []
    public private(set) var notice: PromptNotice?
    /// At most this many prompts are kept; the oldest finished one goes first.
    public var maxRows = 4
    /// How long a finished prompt stays on the board.
    public var finalLinger: Duration = .seconds(6)
    /// A "listening" row whose words never arrived (the speech was abandoned) leaves after this long.
    public var listeningLinger: Duration = .seconds(10)
    /// A safety net for a prompt that never reaches a final status.
    public var activeLinger: Duration = .seconds(600)

    public init() {}

    /// Adds the prompt or updates its text and status. A final row is never reopened by a later non-final
    /// report (a late "running" after "stopped" must not revive it).
    public mutating func report(id: Int, text: String, status: PromptStatus, now: ContinuousClock.Instant) {
        if let i = rows.firstIndex(where: { $0.id == id }) {
            if rows[i].status.isFinal && !status.isFinal { return }
            rows[i].text = text
            rows[i].status = status
            rows[i].updatedAt = now
        } else {
            rows.append(PromptRow(id: id, text: text, status: status, updatedAt: now))
        }
        while rows.count > maxRows {
            let victim = rows.firstIndex(where: { $0.status.isFinal }) ?? 0
            rows.remove(at: victim)
        }
    }

    public mutating func notice(_ text: String, for duration: Duration, now: ContinuousClock.Instant) {
        notice = PromptNotice(text: text, until: now.advanced(by: duration))
    }

    /// When a row leaves the board.
    func expiry(of row: PromptRow) -> ContinuousClock.Instant {
        switch row.status {
        case .listening: row.updatedAt.advanced(by: listeningLinger)
        case .heard, .running, .held: row.updatedAt.advanced(by: activeLinger)
        case .done, .failed, .stopped, .dropped, .ignored: row.updatedAt.advanced(by: finalLinger)
        }
    }

    /// Drops rows and the notice whose time is up.
    public mutating func prune(now: ContinuousClock.Instant) {
        rows = visibleRows(now: now)
        if let n = notice, n.until <= now { notice = nil }
    }

    public func visibleRows(now: ContinuousClock.Instant) -> [PromptRow] {
        rows.filter { expiry(of: $0) > now }
    }

    public func visibleNotice(now: ContinuousClock.Instant) -> PromptNotice? {
        guard let n = notice, n.until > now else { return nil }
        return n
    }

    /// The next moment something leaves the board; nil when it is empty.
    public func nextChange(now: ContinuousClock.Instant) -> ContinuousClock.Instant? {
        var times = visibleRows(now: now).map(expiry(of:))
        if let n = visibleNotice(now: now) { times.append(n.until) }
        return times.min()
    }
}
