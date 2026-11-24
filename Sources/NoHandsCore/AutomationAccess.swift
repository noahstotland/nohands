import Foundation

/// How a child process ended: the exit status and its output (stdout and stderr together), a deadline kill, or no start.
public enum ChildResult: Equatable, Sendable {
    case exited(Int, String)
    case timedOut
    case couldNotStart
}

/// The pure part of "dark mode": the Automation permission check's status code to the executor's next step, and the
/// fixed script's result to what the row says. The calls themselves are in `NoHandsMac`.
public enum AutomationAccess {
    public enum Step: Equatable, Sendable {
        case run, ask, startSystemEvents, denied
        case failed(Int)
    }

    public static let systemEventsID = "com.apple.systemevents"
    public static let allowLine = "allow NoHands in the prompt, then say dark mode again"
    public static let deniedLine = "allow NoHands to control System Events: say open automation settings"
    public static let startFailedLine = "couldn't start System Events"
    public static let timeoutLine = "System Events didn't answer: say it again"
    static let deniedCode = -1743

    /// `AEDeterminePermissionToAutomateTarget` without asking: 0 granted, -1743 denied, -1744 never asked, -600 System
    /// Events is not running.
    public static func step(status: Int) -> Step {
        switch status {
        case 0: .run
        case -1744: .ask
        case -1743: .denied
        case -600: .startSystemEvents
        default: .failed(status)
        }
    }

    /// The failure line for a step that does not run the script.
    public static func line(for step: Step) -> String? {
        switch step {
        case .run: nil
        case .ask: allowLine
        case .denied: deniedLine
        case .startSystemEvents: startFailedLine
        case .failed(let code): failedLine(code)
        }
    }

    public static func failedLine(_ code: Int) -> String { "couldn't change dark mode (error \(code))" }

    /// What the row says when the appearance was set: the value the script returned.
    public static func doneLine(_ appearance: Appearance) -> String { appearance == .dark ? "dark mode" : "light mode" }

    /// The script's result: the appearance now in force (`true` is dark), or the failure line. A -1743 in osascript's
    /// error text is the permission removed meanwhile.
    public static func outcome(_ result: ChildResult) -> Result<Appearance, Failure> {
        switch result {
        case .timedOut: return .failure(Failure(timeoutLine))
        case .couldNotStart: return .failure(Failure(failedLine(-1)))
        case .exited(let status, let output):
            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if status == 0 {
                switch text {
                case "true": return .success(.dark)
                case "false": return .success(.light)
                default: return .failure(Failure(failedLine(0)))
                }
            }
            let code = errorCode(in: text) ?? status
            return .failure(Failure(code == deniedCode ? deniedLine : failedLine(code)))
        }
    }

    public struct Failure: Error, Equatable, Sendable {
        public let line: String
        init(_ line: String) { self.line = line }
    }

    /// The number in osascript's `... (-1743)` error text, nil when there is none.
    static func errorCode(in text: String) -> Int? {
        guard let close = text.lastIndex(of: ")"), let open = text[..<close].lastIndex(of: "(") else { return nil }
        return Int(text[text.index(after: open)..<close])
    }
}

/// Do Not Disturb has no public API: NoHands runs a Shortcut the user made, by one of two fixed names.
public enum DoNotDisturb {
    public static let timeoutLine = "the shortcut didn't finish"

    public static func shortcutName(on: Bool) -> String { on ? "NoHands Do Not Disturb On" : "NoHands Do Not Disturb Off" }
    public static func doneLine(on: Bool) -> String { on ? "do not disturb on" : "do not disturb off" }

    /// The failure line for a shortcut run: nil when it exited 0. `list` is `shortcuts list`'s output, nil when it
    /// could not run; the name must be one whole line of it.
    public static func failure(_ result: ChildResult, on: Bool, list: String?) -> String? {
        let name = shortcutName(on: on)
        switch result {
        case .exited(0, _): return nil
        case .timedOut: return timeoutLine
        case .exited, .couldNotStart:
            let present = list.map { $0.split(whereSeparator: \.isNewline).contains { $0 == name } } ?? true
            return present ? "the \(name) shortcut failed" : "no shortcut called \(name): make it in Shortcuts"
        }
    }
}
