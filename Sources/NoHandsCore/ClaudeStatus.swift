import Foundation

public enum ClaudeCheckKind: Equatable, Sendable {
    case connected, requestRejected, keyRejected, modelNotFound, rateLimited
    case unavailable(Int)
    case timedOut, noNetwork, noKey
}

/// The outcome of one connection check. `detail` is the API's own error type and message, redacted and capped; it is
/// shown in the menu and CLI only, never logged.
public struct ClaudeCheckResult: Equatable, Sendable {
    public let kind: ClaudeCheckKind
    public let statusCode: Int?
    public let detail: String?

    public init(kind: ClaudeCheckKind, statusCode: Int? = nil, detail: String? = nil) {
        self.kind = kind; self.statusCode = statusCode; self.detail = detail
    }

    public static let noKey = ClaudeCheckResult(kind: .noKey)
    public static let timedOut = ClaudeCheckResult(kind: .timedOut)
    public static let noNetwork = ClaudeCheckResult(kind: .noNetwork)

    static let maxBodyBytes = 64 * 1024
    static let maxDetail = 500
    static let menuDetail = 70

    /// Maps an HTTP response to a result. `apiKey` is only used to redact the detail.
    public static func from(status: Int, body: Data, apiKey: String) -> ClaudeCheckResult {
        let kind: ClaudeCheckKind
        switch status {
        case 200..<300: return ClaudeCheckResult(kind: .connected, statusCode: status)
        case 400: kind = .requestRejected
        case 401, 403: kind = .keyRejected
        case 404: kind = .modelNotFound
        case 429: kind = .rateLimited
        default: kind = .unavailable(status)
        }
        return ClaudeCheckResult(kind: kind, statusCode: status, detail: detail(from: body, apiKey: apiKey))
    }

    /// `error.type: error.message` from a JSON body, or nil. Redaction comes before any cut, so a truncated key
    /// cannot survive.
    static func detail(from body: Data, apiKey: String) -> String? {
        guard body.count <= maxBodyBytes,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any] else { return nil }
        var text = [error["type"], error["message"]].compactMap { $0 as? String }.joined(separator: ": ")
        if !apiKey.isEmpty { text = text.replacingOccurrences(of: apiKey, with: "[hidden]") }
        text = text.replacingOccurrences(of: "sk-ant-[A-Za-z0-9_-]*", with: "[hidden]", options: .regularExpression)
        let spaced = String(String.UnicodeScalarView(text.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : $0
        }))
        let collapsed = spaced.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : String(collapsed.prefix(maxDetail))
    }

    /// Short name and status code for the log; never the detail.
    public var logSummary: String {
        "\(kind) \(statusCode.map(String.init) ?? "-")"
    }

    /// The menu line, with `time` (such as `14:32`) already formatted. Nil for no key: the plain status line covers it.
    public func menuText(at time: String) -> String? {
        let at = " at \(time)"
        switch kind {
        case .connected: return "Claude: connected\(at)"
        case .requestRejected:
            return "Claude: request rejected\(at)" + (detail.map { ": " + String($0.prefix(Self.menuDetail)) } ?? "")
        case .keyRejected: return "Claude: key rejected\(at), check anthropicAPIKey"
        case .modelNotFound: return "Claude: model not found\(at), check intentModel"
        case .rateLimited: return "Claude: rate limited\(at), try again soon"
        case .unavailable(let code): return "Claude: unavailable\(at) (HTTP \(code)), try again later"
        case .timedOut: return "Claude: timed out\(at), check your connection"
        case .noNetwork: return "Claude: no network\(at), check your connection"
        case .noKey: return nil
        }
    }

    /// What `nohands-cli claude-check` prints: a headline, then the API's message when there is one.
    public func cliText(model: String) -> String {
        let code = statusCode.map { "HTTP \($0), " } ?? ""
        let head: String
        switch kind {
        case .connected: head = "Claude: connected (HTTP \(statusCode ?? 200), model \(model))"
        case .requestRejected: head = "Claude: request rejected (\(code)model \(model))"
        case .keyRejected: head = "Claude: key rejected (\(code)check anthropicAPIKey)"
        case .modelNotFound: head = "Claude: model not found (\(code)model \(model), check intentModel)"
        case .rateLimited: head = "Claude: rate limited (\(code)try again soon)"
        case .unavailable(let status): head = "Claude: unavailable (HTTP \(status), try again later)"
        case .timedOut: head = "Claude: timed out (check your connection)"
        case .noNetwork: head = "Claude: no network (check your connection)"
        case .noKey: head = "Claude: no key (add anthropicAPIKey to config.json or set ANTHROPIC_API_KEY)"
        }
        return detail.map { head + "\n" + $0 } ?? head
    }
}

/// The Claude line in the menu. It reads the config and the last check only; nothing here touches the network.
public enum ClaudeStatus {
    public static func hasKey(_ config: AppConfig) -> Bool { !(config.anthropicAPIKey ?? "").isEmpty }

    /// The line from the config alone.
    public static func plainLine(_ config: AppConfig) -> String {
        switch config.intentBackend {
        case .local, .off:
            return "Claude: not used (intentBackend = \(config.intentBackend.rawValue))"
        case .auto, .claude:
            guard hasKey(config) else {
                return config.intentBackend == .auto
                    ? "Claude: no key, using the local model"
                    : "Claude: no key, LLM off (add anthropicAPIKey)"
            }
            switch config.anthropicKeySource {
            case .file?: return "Claude: key set (config.json)"
            case .environment?: return "Claude: key set (ANTHROPIC_API_KEY)"
            case nil: return "Claude: key set"
            }
        }
    }

    /// `checking…` while a check runs, else the last result when there is one, else the plain line.
    public static func menuLine(config: AppConfig, checking: Bool, last: (result: ClaudeCheckResult, time: String)?) -> String {
        if checking { return "Claude: checking…" }
        return last.flatMap { $0.result.menuText(at: $0.time) } ?? plainLine(config)
    }
}
