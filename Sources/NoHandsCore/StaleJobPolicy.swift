import Foundation

/// Drops utterances that waited too long behind a slow action (LLM call, app launch): running them late
/// would act on whatever window has focus by then.
public enum StaleJobPolicy {
    public static let defaultMaxAge: Duration = .seconds(8)

    public static func isStale(age: Duration, maxAge: Duration = defaultMaxAge) -> Bool { age > maxAge }
}

/// Group/world-readable config files holding an API key deserve a warning.
public enum ConfigFileSecurity {
    public static func isTooOpen(posixPermissions: Int) -> Bool { posixPermissions & 0o077 != 0 }
}

/// What the menu's status line says, and whether "Retry" shows.
public enum MenuState: Equatable, Sendable {
    case loading, listening, paused, needsAccessibility, microphoneDenied
    case error(String)

    public var text: String {
        switch self {
        case .loading: "Loading speech model…"
        case .listening: "Listening"
        case .paused: "Paused"
        case .needsAccessibility: "Needs Accessibility"
        case .microphoneDenied: "Microphone denied"
        case .error(let m): "Error: \(m)"
        }
    }

    public var showsRetry: Bool { if case .error = self { true } else { false } }

    /// Priority: permissions, then errors, then loading, pause, listening.
    public static func resolve(micDenied: Bool, accessibilityGranted: Bool, error: String?,
                               pipelineReady: Bool, paused: Bool) -> MenuState {
        if micDenied { return .microphoneDenied }
        if !accessibilityGranted { return .needsAccessibility }
        if let error { return .error(error) }
        if !pipelineReady { return .loading }
        return paused ? .paused : .listening
    }

    /// Menu-bar title text: mode label, prefixed with a pause glyph while paused.
    public static func title(mode: Mode, paused: Bool) -> String {
        let label: String
        switch mode {
        case .command: label = "CMD"
        case .dictation: label = "DICT"
        case .sleep: label = "ZZZ"
        }
        return paused ? "⏸ \(label)" : label
    }
}
