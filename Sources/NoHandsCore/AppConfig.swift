import Foundation

public enum IntentBackend: String, Codable, Sendable, CaseIterable { case auto, claude, local, off }
public enum EffectiveBackend: Equatable, Sendable { case claude, local, off }

public struct AppConfig: Codable, Equatable, Sendable {
    public var anthropicAPIKey: String?
    public var intentModel: String = "claude-opus-5-5"
    /// Claude `output_config.effort`: low | medium | high | xhigh | max.
    public var intentEffort: String = "medium"
    public var asrModelVersion: String = "v2"
    /// Trailing silence (ms) before the VAD ends an utterance. 1000 ms lets the user pause mid-command.
    public var silenceMs: Int = 1000
    /// After an utterance is transcribed, wait this long (ms) for speech to resume before acting; if it
    /// resumes, the two pieces are merged into one request. Grammar commands (e.g. "go back") skip the wait.
    public var mergeWindowMs: Int = 500
    /// Same, when the transcript sounds unfinished ("click the", "open").
    public var mergeWindowUnfinishedMs: Int = 1500
    public var gridColumns: Int = 10
    public var gridRows: Int = 8
    public var moveStepPx: Int = 50
    public var scrollStepLines: Int = 5
    public var intentBackend: IntentBackend = .auto
    public var localModel: String?
    public var ollamaURL: String = AppConfig.defaultOllamaURL
    /// Task loop: maximum observe→act steps per task.
    public var maxTaskSteps: Int = 12
    /// Task loop: per-step model deadline (ms).
    public var llmDeadlineMs: Int = 12000
    /// Task loop: how long (ms) to wait for the screen to settle after acting.
    public var settleMs: Int = 3000
    /// Task loop: maximum screen elements sent to the model.
    public var maxObservedElements: Int = 120
    /// Local backend overrides. A 7B model on an M1 Pro prefills 140-670 tokens/s and decodes ~14 tokens/s, so a
    /// step costs 5-20 s; `llmDeadlineMs` is tuned for Claude over the network. Each element adds ~14 prompt tokens.
    public var localLlmDeadlineMs: Int = 30000
    public var localMaxObservedElements: Int = 40

    public static let defaultOllamaURL = "http://127.0.0.1:11434"
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case anthropicAPIKey, intentModel, intentEffort, asrModelVersion, silenceMs, mergeWindowMs, mergeWindowUnfinishedMs
        case gridColumns, gridRows, moveStepPx, scrollStepLines
        case intentBackend, localModel, ollamaURL
        case maxTaskSteps, llmDeadlineMs, settleMs, maxObservedElements
        case localLlmDeadlineMs, localMaxObservedElements
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = AppConfig()
        d.anthropicAPIKey = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey)
        d.intentModel = try c.decodeIfPresent(String.self, forKey: .intentModel) ?? d.intentModel
        d.asrModelVersion = try c.decodeIfPresent(String.self, forKey: .asrModelVersion) ?? d.asrModelVersion
        d.intentEffort = try c.decodeIfPresent(String.self, forKey: .intentEffort) ?? d.intentEffort
        d.silenceMs = try c.decodeIfPresent(Int.self, forKey: .silenceMs) ?? d.silenceMs
        d.mergeWindowMs = try c.decodeIfPresent(Int.self, forKey: .mergeWindowMs) ?? d.mergeWindowMs
        d.mergeWindowUnfinishedMs = try c.decodeIfPresent(Int.self, forKey: .mergeWindowUnfinishedMs) ?? d.mergeWindowUnfinishedMs
        d.gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? d.gridColumns
        d.gridRows = try c.decodeIfPresent(Int.self, forKey: .gridRows) ?? d.gridRows
        d.moveStepPx = try c.decodeIfPresent(Int.self, forKey: .moveStepPx) ?? d.moveStepPx
        d.scrollStepLines = try c.decodeIfPresent(Int.self, forKey: .scrollStepLines) ?? d.scrollStepLines
        // Unknown backend values fall back to .auto instead of invalidating the config.
        d.intentBackend = (try c.decodeIfPresent(String.self, forKey: .intentBackend)).flatMap(IntentBackend.init(rawValue:)) ?? .auto
        d.localModel = try c.decodeIfPresent(String.self, forKey: .localModel)
        d.ollamaURL = try c.decodeIfPresent(String.self, forKey: .ollamaURL) ?? d.ollamaURL
        d.maxTaskSteps = try c.decodeIfPresent(Int.self, forKey: .maxTaskSteps) ?? d.maxTaskSteps
        d.llmDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .llmDeadlineMs) ?? d.llmDeadlineMs
        d.settleMs = try c.decodeIfPresent(Int.self, forKey: .settleMs) ?? d.settleMs
        d.maxObservedElements = try c.decodeIfPresent(Int.self, forKey: .maxObservedElements) ?? d.maxObservedElements
        d.localLlmDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .localLlmDeadlineMs) ?? d.localLlmDeadlineMs
        d.localMaxObservedElements = try c.decodeIfPresent(Int.self, forKey: .localMaxObservedElements) ?? d.localMaxObservedElements
        self = d
    }

    /// Decodes `data` (missing keys → defaults, unknown keys ignored, numeric values clamped);
    /// then `environment["ANTHROPIC_API_KEY"]` overrides the key. Invalid JSON throws.
    public static func load(from data: Data?, environment: [String: String]) throws -> AppConfig {
        var config = AppConfig()
        if let data {
            config = try JSONDecoder().decode(AppConfig.self, from: data)
        }
        config.gridColumns = min(max(config.gridColumns, 1), 40)
        config.gridRows = min(max(config.gridRows, 1), 40)
        config.moveStepPx = min(max(config.moveStepPx, 1), 2000)
        config.scrollStepLines = min(max(config.scrollStepLines, 1), 50)
        config.silenceMs = min(max(config.silenceMs, 100), 3000)
        config.mergeWindowMs = min(max(config.mergeWindowMs, 0), 5000)
        config.mergeWindowUnfinishedMs = min(max(config.mergeWindowUnfinishedMs, config.mergeWindowMs), 5000)
        config.maxTaskSteps = min(max(config.maxTaskSteps, 1), 30)
        config.llmDeadlineMs = min(max(config.llmDeadlineMs, 2000), 60000)
        config.settleMs = min(max(config.settleMs, 0), 10000)
        config.maxObservedElements = min(max(config.maxObservedElements, 10), 300)
        config.localLlmDeadlineMs = min(max(config.localLlmDeadlineMs, 2000), 120000)
        config.localMaxObservedElements = min(max(config.localMaxObservedElements, 10), 300)
        if !AppConfig.efforts.contains(config.intentEffort) { config.intentEffort = AppConfig().intentEffort }
        if let key = environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            config.anthropicAPIKey = key
        }
        return config
    }

    public var grammarConfig: GrammarConfig {
        var g = GrammarConfig()
        g.moveStepPx = moveStepPx
        g.scrollStepLines = scrollStepLines
        return g
    }

    public var effectiveBackend: EffectiveBackend {
        let hasKey = !(anthropicAPIKey ?? "").isEmpty
        switch intentBackend {
        case .auto: return hasKey ? .claude : .local
        case .claude: return hasKey ? .claude : .off
        case .local: return .local
        case .off: return .off
        }
    }

    /// Element cap for the backend in use (each resolver reads its own deadline key).
    public var observedElementCap: Int { effectiveBackend == .local ? localMaxObservedElements : maxObservedElements }

    /// The configured Ollama URL if it is plain `http` to a loopback host; otherwise the default.
    public var ollamaBaseURL: URL {
        let fallback = URL(string: AppConfig.defaultOllamaURL)!
        guard let url = URL(string: ollamaURL), url.scheme == "http",
              let host = url.host?.lowercased(),
              ["127.0.0.1", "localhost", "::1"].contains(host) else { return fallback }
        return url
    }

    public static func defaultLocalModel(physicalMemoryBytes: UInt64) -> String {
        physicalMemoryBytes >= 12 * (1 << 30) ? "qwen2.5:7b-instruct" : "qwen2.5:3b-instruct"
    }

    public var resolvedLocalModel: String {
        localModel ?? AppConfig.defaultLocalModel(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory)
    }
}
