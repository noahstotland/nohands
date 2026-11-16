import Foundation
import NoHandsCore

/// Asks the model to rewrite one piece of text. One request, no retries, no tools: the only thing that comes back is a
/// string, which the executor cleans and types over the text it came from.
public protocol TextRewriting: Sendable {
    func rewrite(_ text: String, _ instruction: RewriteInstruction) async throws -> String
}

/// The rewriter for the backend in effect; nil when the model is off.
public enum TextRewriters {
    public static func make(config: AppConfig, session: URLSession = .shared) -> (any TextRewriting)? {
        switch config.effectiveBackend {
        case .claude: ClaudeTextRewriter(config: config, session: session)
        case .local: OllamaTextRewriter(config: config, session: session)
        case .off: nil
        }
    }
}

/// Rewrites with Claude: the configured model and effort, `llmDeadlineMs`. Token counts go to the session meter.
/// The text and the answer are never logged, only counts.
public actor ClaudeTextRewriter: TextRewriting {
    private let config: AppConfig
    private let session: URLSession
    private let baseURL: URL
    private let deadline: Duration
    private let meter: ClaudeUsageMeter

    /// `baseURL` and `deadline` exist for tests; production uses the defaults.
    public init(config: AppConfig, session: URLSession = .shared, baseURL: URL = ClaudeIntentResolver.endpoint,
                deadline: Duration? = nil, meter: ClaudeUsageMeter = .shared) {
        self.config = config; self.session = session; self.baseURL = baseURL; self.meter = meter
        self.deadline = deadline ?? .milliseconds(config.llmDeadlineMs)
    }

    public func rewrite(_ text: String, _ instruction: RewriteInstruction) async throws -> String {
        guard let key = config.anthropicAPIKey, !key.isEmpty else { throw IntentError.noAPIKey }
        let started = ContinuousClock.now
        let body = RewriteRequestBuilder.claudeBody(model: config.intentModel, effort: config.intentEffort,
                                                    subject: text, instruction: instruction)
        let data = try await ClaudeIntentResolver.send(url: baseURL, key: key, body: body, session: session, deadline: deadline)
        let used = ClaudeUsage.from(response: data)
        meter.record(used)
        let answer = try RewriteResult.decode(fromClaude: data)
        let ms = Int(started.duration(to: .now) / .milliseconds(1))
        PipelineLog.info("claude: rewrite \(instruction.kind) \(text.count)->\(answer.count) chars \(ms)ms \(ClaudeUsage.logFragment(used))")
        return answer
    }
}

/// Rewrites with the local model on loopback: the same model as the task loop, `localLlmDeadlineMs`.
public actor OllamaTextRewriter: TextRewriting {
    private let config: AppConfig
    private let session: URLSession
    private let deadline: Duration

    public init(config: AppConfig, session: URLSession = .shared, deadline: Duration? = nil) {
        self.config = config; self.session = session
        self.deadline = deadline ?? .milliseconds(config.localLlmDeadlineMs)
    }

    public func rewrite(_ text: String, _ instruction: RewriteInstruction) async throws -> String {
        let started = ContinuousClock.now
        let body = RewriteRequestBuilder.ollamaBody(model: config.resolvedLocalModel, subject: text, instruction: instruction)
        let data = try await OllamaIntentResolver.send(body, config: config, session: session, deadline: deadline)
        let answer = try RewriteResult.decode(fromOllama: data)
        let ms = Int(started.duration(to: .now) / .milliseconds(1))
        PipelineLog.info("ollama: rewrite \(instruction.kind) \(text.count)->\(answer.count) chars \(ms)ms")
        return answer
    }
}
