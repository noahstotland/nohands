import Foundation
import NoHandsCore

/// One explicit request that answers "will my Claude commands work?": the app's real step request, asking for one
/// token. Run only on a menu click or `nohands-cli claude-check`; nothing else calls it. The key lives only in the
/// request header; the log gets the result kind and status code, never the API's message.
public struct ClaudeConnectionCheck: Sendable {
    private let config: AppConfig
    private let session: URLSession
    private let baseURL: URL
    private let deadline: Duration
    private let meter: ClaudeUsageMeter

    /// `session`, `baseURL` and `deadline` exist for tests, like `ClaudeIntentResolver`'s.
    public init(config: AppConfig, session: URLSession = .shared,
                baseURL: URL = ClaudeIntentResolver.endpoint, deadline: Duration? = nil,
                meter: ClaudeUsageMeter = .shared) {
        self.config = config
        self.meter = meter
        self.session = session
        self.baseURL = baseURL
        self.deadline = deadline ?? .milliseconds(config.llmDeadlineMs)
    }

    public func run() async -> ClaudeCheckResult {
        guard let key = config.anthropicAPIKey, !key.isEmpty else { return .noKey }
        let builder = ClaudeRequestBuilder(model: config.intentModel, effort: config.intentEffort,
                                           vision: config.visionEnabled)
        let result: ClaudeCheckResult
        do {
            let body = try builder.connectionCheckBody()
            let request = ClaudeIntentResolver.makeRequest(url: baseURL, key: key, deadline: deadline, body: body)
            let (data, http) = try await IntentHTTP.send(request, session: session, deadline: deadline)
            // A 2xx check is a real billed call, so it counts toward the session total.
            if (200..<300).contains(http.statusCode) { meter.record(ClaudeUsage.from(response: data)) }
            result = .from(status: http.statusCode, body: data, apiKey: key)
        } catch let e as IntentError {
            switch e {
            case .timeout, .cancelled: result = .timedOut
            default: result = .noNetwork
            }
        } catch {
            result = ClaudeCheckResult(kind: .requestRejected, detail: "could not build the request")
        }
        PipelineLog.info("claude check: \(result.logSummary)")
        return result
    }
}
