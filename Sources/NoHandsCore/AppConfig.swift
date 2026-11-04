import Foundation

public enum IntentBackend: String, Codable, Sendable, CaseIterable { case auto, claude, local, off }
public enum EffectiveBackend: Equatable, Sendable { case claude, local, off }

public struct AppConfig: Codable, Equatable, Sendable {
    public var anthropicAPIKey: String?
    public var intentModel: String = "claude-opus-5-5"
    public var asrModelVersion: String = "v2"
    public var silenceMs: Int = 350
    public var gridColumns: Int = 10
    public var gridRows: Int = 8
    public var moveStepPx: Int = 50
    public var scrollStepLines: Int = 5
    public var intentBackend: IntentBackend = .auto
    public var localModel: String?
    public var ollamaURL: String = AppConfig.defaultOllamaURL

    public static let defaultOllamaURL = "http://127.0.0.1:11434"

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case anthropicAPIKey, intentModel, asrModelVersion, silenceMs
        case gridColumns, gridRows, moveStepPx, scrollStepLines
        case intentBackend, localModel, ollamaURL
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var d = AppConfig()
        d.anthropicAPIKey = try c.decodeIfPresent(String.self, forKey: .anthropicAPIKey)
        d.intentModel = try c.decodeIfPresent(String.self, forKey: .intentModel) ?? d.intentModel
        d.asrModelVersion = try c.decodeIfPresent(String.self, forKey: .asrModelVersion) ?? d.asrModelVersion
        d.silenceMs = try c.decodeIfPresent(Int.self, forKey: .silenceMs) ?? d.silenceMs
        d.gridColumns = try c.decodeIfPresent(Int.self, forKey: .gridColumns) ?? d.gridColumns
        d.gridRows = try c.decodeIfPresent(Int.self, forKey: .gridRows) ?? d.gridRows
        d.moveStepPx = try c.decodeIfPresent(Int.self, forKey: .moveStepPx) ?? d.moveStepPx
        d.scrollStepLines = try c.decodeIfPresent(Int.self, forKey: .scrollStepLines) ?? d.scrollStepLines
        // Unknown backend values fall back to .auto instead of invalidating the config.
        d.intentBackend = (try c.decodeIfPresent(String.self, forKey: .intentBackend)).flatMap(IntentBackend.init(rawValue:)) ?? .auto
        d.localModel = try c.decodeIfPresent(String.self, forKey: .localModel)
        d.ollamaURL = try c.decodeIfPresent(String.self, forKey: .ollamaURL) ?? d.ollamaURL
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
