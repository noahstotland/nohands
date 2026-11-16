import Foundation

public enum IntentBackend: String, Codable, Sendable, CaseIterable { case auto, claude, local, off }
public enum EffectiveBackend: Equatable, Sendable { case claude, local, off }
/// Where the Anthropic key in effect came from; only for the menu line, never the key itself.
public enum KeySource: Sendable, Equatable { case file, environment }
public enum DesktopHarnessChoice: String, Codable, Sendable, CaseIterable { case auto, agentDesktop, native }

public struct AppConfig: Codable, Equatable, Sendable {
    public var anthropicAPIKey: String?
    /// Set only by `load`; not part of the file format.
    public private(set) var anthropicKeySource: KeySource?
    public var intentModel: String = "claude-haiku-5-5"
    /// Claude `output_config.effort`: low | medium | high | xhigh | max.
    public var intentEffort: String = "low"
    public var asrModelVersion: String = "v2"
    /// Trailing silence (ms) before the VAD ends an utterance. 1000 ms lets the user pause mid-command.
    public var silenceMs: Int = 1000
    /// Trailing silence (ms) after which a phrase that is already a complete grammar command or a stop phrase is acted
    /// on without waiting for `silenceMs`. 0 turns it off. A chunk count underneath (256 ms each), like `silenceMs`.
    public var earlySilenceMs: Int = 350
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
    /// Task loop: the step cap for a goal about playing media (a stream site throws overlays and pop-unders first).
    public var maxMediaTaskSteps: Int = 24
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
    /// Desktop harness for the task loop: `auto` uses agent-desktop when its binary is found and Accessibility is
    /// granted, else the native AX/CGEvent path.
    public var desktopHarness: DesktopHarnessChoice = .auto
    /// Absolute path of the agent-desktop binary; nil searches the usual install locations.
    public var agentDesktopPath: String?
    /// Per-command deadline (ms) for agent-desktop actions.
    public var agentDesktopTimeoutMs: Int = 8000
    /// `--timeout-ms` for snapshots (ms); fixed, never derived from the settle budget.
    public var agentDesktopSnapshotMs: Int = 3000
    /// Retry a harness action once with `--headed` when nothing was delivered.
    public var agentDesktopHeadedFallback: Bool = true
    /// Start an agent-desktop session (with its trace) per task.
    public var agentDesktopTrace: Bool = false
    /// Turn on the system's voice processing (echo cancellation) on the microphone, so audio the Mac's own
    /// speakers play is removed before VAD and ASR. Capture goes on without it if macOS refuses.
    public var echoCancellation: Bool = true
    /// Optional attention word (up to three words). When set, command mode acts only on utterances that start
    /// with it; everything else is ignored silently. Empty means off. `load` stores it normalized, or empty when
    /// it cannot be used (more than three words, or a stop phrase).
    public var attentionWord: String = ""
    /// Task loop, Claude backend only: send a picture of the focused window on steps where the accessibility tree
    /// failed (see `visionEnabled`). Off by default; needs the Screen Recording permission.
    public var visionFallback: Bool = false
    /// The user's own words: misheard spellings swapped for the right ones in every transcript (see `Vocabulary`).
    public private(set) var vocabulary = Vocabulary()

    public static let defaultOllamaURL = "http://127.0.0.1:11434"
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case anthropicAPIKey, intentModel, intentEffort, asrModelVersion, silenceMs, earlySilenceMs, mergeWindowMs, mergeWindowUnfinishedMs
        case gridColumns, gridRows, moveStepPx, scrollStepLines
        case intentBackend, localModel, ollamaURL
        case maxTaskSteps, maxMediaTaskSteps, llmDeadlineMs, settleMs, maxObservedElements
        case localLlmDeadlineMs, localMaxObservedElements
        case desktopHarness, agentDesktopPath, agentDesktopTimeoutMs, agentDesktopSnapshotMs, agentDesktopHeadedFallback, agentDesktopTrace
        case echoCancellation, attentionWord, visionFallback, vocabulary
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = AppConfig()
        d.anthropicAPIKey = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey)
        d.intentModel = try c.decodeIfPresent(String.self, forKey: .intentModel) ?? d.intentModel
        d.asrModelVersion = try c.decodeIfPresent(String.self, forKey: .asrModelVersion) ?? d.asrModelVersion
        d.intentEffort = try c.decodeIfPresent(String.self, forKey: .intentEffort) ?? d.intentEffort
        d.silenceMs = try c.decodeIfPresent(Int.self, forKey: .silenceMs) ?? d.silenceMs
        d.earlySilenceMs = try c.decodeIfPresent(Int.self, forKey: .earlySilenceMs) ?? d.earlySilenceMs
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
        d.maxMediaTaskSteps = try c.decodeIfPresent(Int.self, forKey: .maxMediaTaskSteps) ?? d.maxMediaTaskSteps
        d.llmDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .llmDeadlineMs) ?? d.llmDeadlineMs
        d.settleMs = try c.decodeIfPresent(Int.self, forKey: .settleMs) ?? d.settleMs
        d.maxObservedElements = try c.decodeIfPresent(Int.self, forKey: .maxObservedElements) ?? d.maxObservedElements
        d.localLlmDeadlineMs = try c.decodeIfPresent(Int.self, forKey: .localLlmDeadlineMs) ?? d.localLlmDeadlineMs
        d.localMaxObservedElements = try c.decodeIfPresent(Int.self, forKey: .localMaxObservedElements) ?? d.localMaxObservedElements
        d.desktopHarness = (try c.decodeIfPresent(String.self, forKey: .desktopHarness)).flatMap(DesktopHarnessChoice.init(rawValue:)) ?? .auto
        d.agentDesktopPath = try c.decodeIfPresent(String.self, forKey: .agentDesktopPath)
        d.agentDesktopTimeoutMs = try c.decodeIfPresent(Int.self, forKey: .agentDesktopTimeoutMs) ?? d.agentDesktopTimeoutMs
        d.agentDesktopSnapshotMs = try c.decodeIfPresent(Int.self, forKey: .agentDesktopSnapshotMs) ?? d.agentDesktopSnapshotMs
        d.agentDesktopHeadedFallback = try c.decodeIfPresent(Bool.self, forKey: .agentDesktopHeadedFallback) ?? d.agentDesktopHeadedFallback
        d.agentDesktopTrace = try c.decodeIfPresent(Bool.self, forKey: .agentDesktopTrace) ?? d.agentDesktopTrace
        d.echoCancellation = try c.decodeIfPresent(Bool.self, forKey: .echoCancellation) ?? d.echoCancellation
        d.attentionWord = try c.decodeIfPresent(String.self, forKey: .attentionWord) ?? d.attentionWord
        d.visionFallback = try c.decodeIfPresent(Bool.self, forKey: .visionFallback) ?? d.visionFallback
        // Lenient: a `vocabulary` that is not a list is ignored and counted as one skipped entry; each bad entry is skipped inside `Vocabulary`.
        if c.contains(.vocabulary) {
            d.vocabulary = (try? c.decode(Vocabulary.self, forKey: .vocabulary)) ?? Vocabulary(skipped: 1)
        }
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
        config.earlySilenceMs = min(max(config.earlySilenceMs, 0), 3000)
        config.mergeWindowMs = min(max(config.mergeWindowMs, 0), 5000)
        config.mergeWindowUnfinishedMs = min(max(config.mergeWindowUnfinishedMs, config.mergeWindowMs), 5000)
        config.maxTaskSteps = min(max(config.maxTaskSteps, 1), 30)
        config.maxMediaTaskSteps = min(max(config.maxMediaTaskSteps, 1), 30)
        config.llmDeadlineMs = min(max(config.llmDeadlineMs, 2000), 60000)
        config.settleMs = min(max(config.settleMs, 0), 10000)
        config.maxObservedElements = min(max(config.maxObservedElements, 10), 300)
        config.localLlmDeadlineMs = min(max(config.localLlmDeadlineMs, 2000), 120000)
        config.localMaxObservedElements = min(max(config.localMaxObservedElements, 10), 300)
        config.agentDesktopTimeoutMs = min(max(config.agentDesktopTimeoutMs, 1000), 60000)
        config.agentDesktopSnapshotMs = min(max(config.agentDesktopSnapshotMs, 500), 10000)
        config.anthropicKeySource = (config.anthropicAPIKey ?? "").isEmpty ? nil : .file
        config.attentionWord = AttentionGate(configured: config.attentionWord).words.joined(separator: " ")
        if !AppConfig.efforts.contains(config.intentEffort) { config.intentEffort = AppConfig().intentEffort }
        if let key = environment["ANTHROPIC_API_KEY"], !key.isEmpty {
            config.anthropicAPIKey = key
            config.anthropicKeySource = .environment
        }
        return config
    }

    public var grammarConfig: GrammarConfig {
        var g = GrammarConfig()
        g.moveStepPx = moveStepPx
        g.scrollStepLines = scrollStepLines
        return g
    }

    public var attentionGate: AttentionGate { AttentionGate(configured: attentionWord) }

    public var effectiveBackend: EffectiveBackend {
        let hasKey = !(anthropicAPIKey ?? "").isEmpty
        switch intentBackend {
        case .auto: return hasKey ? .claude : .local
        case .claude: return hasKey ? .claude : .off
        case .local: return .local
        case .off: return .off
        }
    }

    /// Pictures are sent only with the flag on and Claude as the backend; the local model never gets one.
    public var visionEnabled: Bool { visionFallback && effectiveBackend == .claude }

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
