import Foundation
import NoHandsCore

public enum IntentError: Error {
    case noAPIKey
    case network(Error)
    case http(Int, String)
    case decode(IntentDecodeError)
    case timeout
    case cancelled
    case localUnavailable
    case modelMissing
}

public protocol IntentResolving: Sendable {
    func resolve(_ request: StepRequest) async throws -> IntentStep
}

extension IntentResolving {
    /// One-shot convenience: step 1 of a fresh request, returning just the actions.
    public func resolve(_ transcript: String, context: IntentContext) async throws -> [Action] {
        try await resolve(StepRequest(oneShot: transcript, context: context)).actions
    }
}

/// Sends one request (no retries) to the Anthropic Messages API and decodes the actions.
/// The API key lives only in the request header; it is never logged or put in an error.
public actor ClaudeIntentResolver: IntentResolving {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let bodyPrefixLimit = 200

    private let config: AppConfig
    private let session: URLSession
    private let baseURL: URL
    private let deadline: Duration

    /// `baseURL` and `deadline` exist for tests; production uses the defaults.
    public init(config: AppConfig, session: URLSession = .shared,
                baseURL: URL = ClaudeIntentResolver.endpoint,
                deadline: Duration? = nil) {
        self.config = config
        self.session = session
        self.baseURL = baseURL
        self.deadline = deadline ?? .milliseconds(config.llmDeadlineMs)
    }

    public func resolve(_ stepRequest: StepRequest) async throws -> IntentStep {
        guard let key = config.anthropicAPIKey, !key.isEmpty else { throw IntentError.noAPIKey }
        let builder = ClaudeRequestBuilder(model: config.intentModel, effort: config.intentEffort)
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(deadline.components.seconds) + 2
        for (name, value) in ClaudeRequestBuilder.headers(key) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try builder.body(request: stepRequest)
        } catch {
            throw IntentError.decode(.malformed("could not encode request"))
        }

        let started = ContinuousClock.now
        let (data, http) = try await IntentHTTP.send(request, session: session, deadline: deadline)
        if !(200..<300).contains(http.statusCode) {
            let text = String(decoding: data.prefix(Self.bodyPrefixLimit * 4), as: UTF8.self)
            throw IntentError.http(http.statusCode, String(text.prefix(Self.bodyPrefixLimit)))
        }
        // Counts and timing only; logged before decoding so a malformed step still shows its cache numbers.
        let ms = Int(started.duration(to: .now) / .milliseconds(1))
        PipelineLog.info("claude: step \(stepRequest.step) \(ms)ms \(ClaudeUsage.logFragment(ClaudeUsage.from(response: data)))")
        do {
            return try IntentDecoder.step(fromResponse: data)
        } catch let e as IntentDecodeError {
            throw IntentError.decode(e)
        }
    }
}

/// The request context plus the exact label snapshot it numbered, so `.label(n)` actions can be resolved
/// against what the model was shown.
public struct IntentContextBundle: Sendable {
    public var context: IntentContext
    public var labels: [Int: UIElementInfo]
    public var observation: ScreenObservation
}

public enum IntentContextBuilder {
    public static func make(elements: ElementProviding, mode: Mode, maxElements: Int = 60,
                            overlay: OverlayState = .none) -> IntentContext {
        makeBundle(elements: elements, mode: mode, maxElements: maxElements, overlay: overlay).context
    }

    /// `labels` holds only the elements actually listed in the context (titled, within `maxElements`).
    public static func makeBundle(elements: ElementProviding, mode: Mode, maxElements: Int = 60,
                                  overlay: OverlayState = .none) -> IntentContextBundle {
        let (observation, snapshot) = ScreenObserver(ax: elements, maxElements: maxElements)
            .observe(mode: mode, overlay: overlay)
        let context = IntentContext(frontmostApp: observation.app, mode: mode,
                                    labeledElements: observation.elements.map { (number: $0.number, title: $0.title) },
                                    overlay: observation.overlay)
        return IntentContextBundle(context: context, labels: snapshot, observation: observation)
    }
}
