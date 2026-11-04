import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var anthropicAPIKey: String?
    public var intentModel: String = "claude-opus-5-5"
    public var asrModelVersion: String = "v2"
    public var silenceMs: Int = 350
    public var gridColumns: Int = 10
    public var gridRows: Int = 8
    public var moveStepPx: Int = 50
    public var scrollStepLines: Int = 5

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case anthropicAPIKey, intentModel, asrModelVersion, silenceMs
        case gridColumns, gridRows, moveStepPx, scrollStepLines
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
}
