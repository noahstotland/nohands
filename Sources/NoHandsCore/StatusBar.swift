import Foundation

/// Where the always-on status bar sits (the menu's Status Bar submenu). Stored by the app; Core only parses it.
public enum StatusBarPosition: String, CaseIterable, Sendable {
    case off, top, bottom

    /// A missing or unknown stored value means the default: on, at the top.
    public static func stored(_ raw: String?) -> StatusBarPosition {
        raw.flatMap(StatusBarPosition.init(rawValue:)) ?? .top
    }
}

/// The one line the status bar shows, and its colour.
public struct StatusLine: Equatable, Sendable {
    public let text: String
    public let tone: PromptStatus.Tone
}

/// Picks what the status bar says from the app state, the mode and the prompt board's visible rows.
public enum StatusBarText {
    public static func line(menu: MenuState, mode: Mode, rows: [PromptRow]) -> StatusLine {
        switch menu {
        case .microphoneDenied:
            return StatusLine(text: "Microphone denied: allow NoHands in System Settings", tone: .bad)
        case .needsAccessibility:
            return StatusLine(text: "Needs Accessibility: allow NoHands in System Settings", tone: .bad)
        case .error(let message):
            return StatusLine(text: "Error: \(message) · choose Retry in the menu", tone: .bad)
        case .loading:
            return StatusLine(text: "Loading speech model…", tone: .waiting)
        case .paused:
            return StatusLine(text: "Paused · Resume Listening in the menu", tone: .muted)
        case .listening:
            break
        }
        if let row = liveRow(rows) ?? rows.filter({ $0.status.isFinal }).max(by: newer) {
            return StatusLine(text: "\(row.text) · \(row.status.text)", tone: row.status.tone)
        }
        switch mode {
        case .sleep: return StatusLine(text: "Asleep · say wake up", tone: .muted)
        case .dictation: return StatusLine(text: "Dictating · say stop dictating", tone: .active)
        case .command: return StatusLine(text: "Listening", tone: .good)
        }
    }

    /// The live row to show: a running task first, then heard, listening, held; the newest within a kind.
    private static func liveRow(_ rows: [PromptRow]) -> PromptRow? {
        func rank(_ s: PromptStatus) -> Int {
            switch s {
            case .running: 3
            case .heard: 2
            case .listening: 1
            default: 0
            }
        }
        return rows.filter { !$0.status.isFinal }
            .max { a, b in rank(a.status) != rank(b.status) ? rank(a.status) < rank(b.status) : newer(a, b) }
    }

    /// True when `a` is older than `b` (ties go to the later prompt).
    private static func newer(_ a: PromptRow, _ b: PromptRow) -> Bool {
        a.updatedAt != b.updatedAt ? a.updatedAt < b.updatedAt : a.id < b.id
    }
}
