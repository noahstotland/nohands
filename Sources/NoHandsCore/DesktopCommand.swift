import Foundation
import CoreGraphics

/// An agent-desktop surface other than the window: the model names them with underscores, the CLI with dashes.
public enum DesktopSurface: String, Codable, Sendable, CaseIterable {
    case menubar, menu, sheet, alert, popover, dock
    case menuBarExtras = "menu_bar_extras"
    public var cliName: String { rawValue.replacingOccurrences(of: "_", with: "-") }
}

public enum DesktopWindowOp: String, Codable, Sendable, CaseIterable { case minimize, maximize, restore, focus }

public enum DesktopWaitKind: String, Codable, Sendable, CaseIterable {
    case text, window, event, menu
    case menuClosed = "menu_closed"
    case element
    /// Answered by NoHands itself (no agent-desktop condition exists), so it never becomes a `DesktopCommand`.
    case mediaPlaying = "media_playing"
}

public enum DesktopEvent: String, Codable, Sendable, CaseIterable {
    case windowOpened = "window_opened", windowClosed = "window_closed"
    case appLaunched = "app_launched", appTerminated = "app_terminated"
    case focusChanged = "focus_changed"
    case surfaceAppeared = "surface_appeared", surfaceDismissed = "surface_dismissed"
    public var cliName: String { rawValue.replacingOccurrences(of: "_", with: "-") }
}

/// A typed agent-desktop invocation; `argv` is what the binary receives after its own name.
public enum DesktopCommand: Equatable, Sendable {
    case version, status
    case snapshot(app: String?, windowID: String?, surface: DesktopSurface?, timeoutMs: Int)
    case find(app: String?, surface: DesktopSurface?, name: String, exact: Bool)
    case listWindows(app: String?)
    case listSurfaces(app: String)
    case click(ref: String, button: MouseButton, count: Int)
    case type(ref: String, text: String)
    case setValue(ref: String, text: String)
    case clear(ref: String)
    case select(ref: String, option: String)
    case check(ref: String, Bool)
    case toggle(ref: String)
    case expand(ref: String, Bool)
    case focus(ref: String)
    case scrollTo(ref: String)
    case scroll(ref: String, Direction, amount: Int)
    case drag(fromRef: String?, fromXY: CGPoint?, toRef: String?, toXY: CGPoint?)
    case closeApp(String)
    case window(DesktopWindowOp, app: String?, title: String?)
    case clipboardGet
    case clipboardSet(text: String)
    case get(ref: String, property: String)
    case listNotifications
    case dismissAllNotifications(app: String?)
    case wait(DesktopWaitKind, value: String?, app: String?, ref: String?, timeoutMs: Int)
    case sessionStart(name: String)
    case sessionEnd(id: String)

    /// Reads only: a timeout or failure delivered nothing to any app.
    public var isObservation: Bool {
        switch self {
        case .version, .status, .snapshot, .find, .listWindows, .listSurfaces, .clipboardGet, .get, .listNotifications: true
        default: false
        }
    }

    /// Has no headless path in agent-desktop: always sent with `--headed`.
    public var needsHeaded: Bool {
        switch self {
        case .drag, .listNotifications, .dismissAllNotifications: true
        case .click(_, _, let count): count > 1
        default: false
        }
    }

    /// The subcommand word (`set-value`, `double-click`, ...).
    public var commandName: String {
        switch self {
        case .version: "version"
        case .status: "status"
        case .snapshot: "snapshot"
        case .find: "find"
        case .listWindows: "list-windows"
        case .listSurfaces: "list-surfaces"
        case .click(_, let button, let count):
            button == .right ? "right-click" : count >= 3 ? "triple-click" : count == 2 ? "double-click" : "click"
        case .type: "type"
        case .setValue: "set-value"
        case .clear: "clear"
        case .select: "select"
        case .check(_, let on): on ? "check" : "uncheck"
        case .toggle: "toggle"
        case .expand(_, let open): open ? "expand" : "collapse"
        case .focus: "focus"
        case .scrollTo: "scroll-to"
        case .scroll: "scroll"
        case .drag: "drag"
        case .closeApp: "close-app"
        case .window(let op, _, _): op == .focus ? "focus-window" : op.rawValue
        case .clipboardGet: "clipboard-get"
        case .clipboardSet: "clipboard-set"
        case .get: "get"
        case .listNotifications: "list-notifications"
        case .dismissAllNotifications: "dismiss-all-notifications"
        case .wait: "wait"
        case .sessionStart, .sessionEnd: "session"
        }
    }

    /// Global flags first (`--headed` when asked or required, `--session` for everything but `version`), then the
    /// subcommand and its own arguments.
    public func argv(headed: Bool, session: String?) -> [String] {
        var out: [String] = []
        if headed || needsHeaded { out.append("--headed") }
        if let session, self != .version { out += ["--session", session] }
        out.append(contentsOf: commandName.split(separator: " ").map(String.init))
        switch self {
        case .version, .status, .clipboardGet, .listNotifications:
            break
        case .snapshot(let app, let windowID, let surface, let timeoutMs):
            if let app { out += ["--app", app] }
            if let windowID { out += ["--window-id", windowID] }
            if let surface { out += ["--surface", surface.cliName] }
            out += ["-i", "--compact", "--include-bounds", "--max-depth", "25", "--timeout-ms", String(timeoutMs)]
        case .find(let app, let surface, let name, let exact):
            if let app { out += ["--app", app] }
            if let surface { out += ["--surface", surface.cliName] }
            out += ["--name", name]
            if exact { out.append("--exact") }
            out.append("--first")
        case .listWindows(let app):
            if let app { out += ["--app", app] }
        case .listSurfaces(let app):
            out += ["--app", app]
        case .click(let ref, _, _), .clear(let ref), .toggle(let ref), .focus(let ref), .scrollTo(let ref),
             .check(let ref, _), .expand(let ref, _):
            out.append(ref)
        case .type(let ref, let text), .setValue(let ref, let text):
            out += [ref, text]
        case .select(let ref, let option):
            out += [ref, option]
        case .scroll(let ref, let direction, let amount):
            out += [ref, "--direction", direction.rawValue, "--amount", String(amount)]
        case .drag(let fromRef, let fromXY, let toRef, let toXY):
            if let fromRef { out += ["--from", fromRef] } else if let fromXY { out += ["--from-xy", Self.xy(fromXY)] }
            if let toRef { out += ["--to", toRef] } else if let toXY { out += ["--to-xy", Self.xy(toXY)] }
        case .closeApp(let app):
            out.append(app)
        case .window(let op, let app, let title):
            if let app { out += ["--app", app] }
            if let title, op == .focus { out += ["--title", title] }   // only focus-window takes --title
        case .clipboardSet(let text):
            out.append(text)
        case .get(let ref, let property):
            out += [ref, "--property", property]
        case .dismissAllNotifications(let app):
            if let app { out += ["--app", app] }
        case .wait(let kind, let value, let app, let ref, let timeoutMs):
            switch kind {
            case .text: out += ["--text", value ?? ""]
            case .window: out += ["--window", value ?? ""]
            case .event: out += ["--event", DesktopEvent(rawValue: value ?? "")?.cliName ?? value ?? ""]
            case .menu: out.append("--menu")
            case .menuClosed: out.append("--menu-closed")
            case .element: out += ["--element", ref ?? "", "--predicate", value ?? "exists"]
            case .mediaPlaying: break   // the executor answers it; never sent to agent-desktop
            }
            if let app { out += ["--app", app] }
            out += ["--timeout", String(timeoutMs)]
        case .sessionStart(let name):
            out += ["start", "--name", name]
        case .sessionEnd(let id):
            out += ["end", id]
        }
        return out
    }

    /// Rounded integer `x,y`: agent-desktop takes whole screen pixels.
    private static func xy(_ p: CGPoint) -> String { "\(Int(p.x.rounded())),\(Int(p.y.rounded()))" }
}
