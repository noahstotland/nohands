import Foundation

/// The two backends the Model submenu can pick. `auto` and `off` stay file-only.
public enum BackendChoice: String, Sendable, CaseIterable { case claude, local }

/// Logic behind the Model submenu: the config patch and what each row shows.
public enum BackendMenu {
    public struct Row: Equatable, Sendable {
        public let choice: BackendChoice
        public let title: String
        public let checked: Bool
        public let enabled: Bool
    }

    /// `existing` (nil means no file, treated as `{}`) with `intentBackend` set to `choice` and nothing else changed.
    /// Same parse and format rules as `ClaudeKeyEntry.merged`, which it shares code with.
    public static func merged(existing: Data?, choice: BackendChoice) throws -> Data {
        try ConfigPatch.merged(existing: existing, key: "intentBackend", value: choice.rawValue)
    }

    /// The top menu item, from the backend actually in use (`auto` shows what it resolved to).
    public static func title(config: AppConfig) -> String {
        switch config.effectiveBackend {
        case .claude: return "Model: Claude"
        case .local: return "Model: Local"
        case .off: return "Model: Off"
        }
    }

    public static func rows(config: AppConfig, keySavedThisSession: Bool) -> [Row] {
        let effective = config.effectiveBackend
        let hasKey = !(config.anthropicAPIKey ?? "").isEmpty
        let claudeTitle: String
        if hasKey {
            claudeTitle = "Claude"
        } else if keySavedThisSession {
            claudeTitle = "Claude (restart NoHands to use the new key)"
        } else {
            claudeTitle = "Claude (choose Set Claude API key… first)"
        }
        return [
            Row(choice: .claude, title: claudeTitle, checked: effective == .claude, enabled: hasKey),
            Row(choice: .local, title: "Local model", checked: effective == .local, enabled: true),
        ]
    }
}
