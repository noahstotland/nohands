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
        self.deadline = deadline ?? .milliseconds(config.llmDeadlineMs)
    }

    public func resolve(_ stepRequest: StepRequest) async throws -> IntentStep {
        var request = URLRequest(url: config.ollamaBaseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(deadline.components.seconds) + 2
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try OllamaRequestBuilder(model: config.resolvedLocalModel)
                .body(request: stepRequest)
        } catch {
            throw IntentError.decode(.malformed("could not encode request"))
        }

        let data: Data
        let http: HTTPURLResponse
        do {
            (data, http) = try await IntentHTTP.send(request, session: session, deadline: deadline)
        } catch .network(let underlying) {
            if let e = underlying as NSError?, e.domain == NSURLErrorDomain, Self.refusedCodes.contains(e.code) {
                throw IntentError.localUnavailable
            }
            throw IntentError.network(underlying)
        }

        guard (200..<300).contains(http.statusCode) else {
            let text = String(decoding: data.prefix(Self.bodyPrefixLimit * 4), as: UTF8.self)
            if http.statusCode == 404, text.contains("not found") { throw IntentError.modelMissing }
            throw IntentError.http(http.statusCode, String(text.prefix(Self.bodyPrefixLimit)))
        }
        do {
            return try IntentDecoder.step(fromOllamaResponse: data)
        } catch let e as IntentDecodeError {
            throw IntentError.decode(e)
        }
    }

    private static let refusedCodes: Set<Int> = [
        URLError.cannotConnectToHost.rawValue,
        URLError.cannotFindHost.rawValue,
        URLError.networkConnectionLost.rawValue,
    ]
}
