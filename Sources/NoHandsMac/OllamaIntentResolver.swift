import Foundation
import NoHandsCore

/// Resolves a transcript with a local Ollama model. One request, no retries, hard deadline.
public actor OllamaIntentResolver: IntentResolving {
    static let bodyPrefixLimit = 200

    private let config: AppConfig
    private let session: URLSession
    private let deadline: Duration

    public init(config: AppConfig, session: URLSession = .shared, deadline: Duration? = nil) {
        self.config = config
        self.session = session
        self.deadline = deadline ?? .milliseconds(config.localLlmDeadlineMs)
    }

    public func resolve(_ stepRequest: StepRequest) async throws -> IntentStep {
        let body: Data
        do {
            body = try OllamaRequestBuilder(model: config.resolvedLocalModel).body(request: stepRequest)
        } catch {
            throw IntentError.decode(.malformed("could not encode request"))
        }
        let started = ContinuousClock.now
        let data = try await post(body)
        let step: IntentStep
        do {
            step = try IntentDecoder.step(fromOllamaResponse: data)
        } catch let e as IntentDecodeError {
            throw IntentError.decode(e)
        }
        let ms = Int(started.duration(to: .now) / .milliseconds(1))
        PipelineLog.info("ollama: step \(stepRequest.step) \(ms)ms")
        return step
    }

    public func plan(goal: String) async throws -> TaskPlan? {
        let started = ContinuousClock.now
        let data = try await post(OllamaRequestBuilder(model: config.resolvedLocalModel).planBody(goal: goal))
        let plan = TaskPlan.decode(fromOllamaResponse: data)
        let ms = Int(started.duration(to: .now) / .milliseconds(1))
        PipelineLog.info("ollama: plan \(ms)ms \(plan.map { "\($0.steps.count) steps" } ?? "none")")
        return plan
    }

    /// One POST to the local model; returns the 2xx response body.
    private func post(_ body: Data) async throws -> Data {
        try await Self.send(body, config: config, session: session, deadline: deadline)
    }

    /// The one local POST, shared with the rewrite request. A refused connection is `localUnavailable`, an unknown
    /// model `modelMissing`.
    static func send(_ body: Data, config: AppConfig, session: URLSession, deadline: Duration) async throws -> Data {
        var request = URLRequest(url: config.ollamaBaseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(deadline.components.seconds) + 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await IntentHTTP.send(request, session: session, deadline: deadline)
        } catch .network(let underlying) {
            if let e = underlying as NSError?, e.domain == NSURLErrorDomain, refusedCodes.contains(e.code) {
                throw IntentError.localUnavailable
            }
            throw IntentError.network(underlying)
        }

        guard (200..<300).contains(http.statusCode) else {
            let text = String(decoding: data.prefix(bodyPrefixLimit * 4), as: UTF8.self)
            if http.statusCode == 404, text.contains("not found") { throw IntentError.modelMissing }
            throw IntentError.http(http.statusCode, String(text.prefix(bodyPrefixLimit)))
        }
        return data
    }

    private static let refusedCodes: Set<Int> = [
        URLError.cannotConnectToHost.rawValue,
        URLError.cannotFindHost.rawValue,
        URLError.networkConnectionLost.rawValue,
    ]
}
