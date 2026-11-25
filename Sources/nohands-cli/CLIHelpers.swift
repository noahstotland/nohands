import Foundation
import NoHandsCore
import NoHandsMac

// Shared by main.swift and Scenarios.swift. They live here because the compiler cannot reference a function that
// main.swift declares after its top-level statements from another file.

/// Loads `~/.config/nohands/config.json` (plus environment) and builds the configured backend's resolver.
/// `model` and `effort` override the Claude settings for this run only (the config file is not touched).
func loadResolver(model: String? = nil, effort: String? = nil) throws -> (config: AppConfig, resolver: any IntentResolving, model: String) {
    let cfgURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/config.json")
    var config = try AppConfig.load(from: try? Data(contentsOf: cfgURL), environment: ProcessInfo.processInfo.environment)
    if config.effectiveBackend == .local, model != nil || effort != nil {
        fail("error: --model and --effort apply to the Claude backend")
    }
    if let model { config.intentModel = model }
    if let effort { config.intentEffort = effort }
    switch config.effectiveBackend {
    case .claude: return (config, ClaudeIntentResolver(config: config), config.intentModel)
    case .local: return (config, OllamaIntentResolver(config: config), config.resolvedLocalModel)
    case .off: fail("error: LLM off")
    }
}

func ms(_ d: Duration) -> Int { Int(d / .milliseconds(1)) }

/// Runs `body` on the main actor with an overlay (the app's run loop is already running; see `runCommand`).
@MainActor func runOverlay(_ body: @MainActor (OverlayController) async -> Void) async {
    await body(OverlayController())
}

func sanitized(_ s: String) -> String {
    String(s.unicodeScalars.map { $0.properties.generalCategory == .control || $0.properties.generalCategory == .lineSeparator || $0.properties.generalCategory == .paragraphSeparator ? " " : Character($0) })
}
