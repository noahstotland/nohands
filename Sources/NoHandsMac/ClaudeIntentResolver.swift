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
    func resolve(_ transcript: String, context: IntentContext) async throws -> [Action]
}

/// Sends one request (no retries) to the Anthropic Messages API and decodes the actions.
/// The API key lives only in the request header; it is never logged or put in an error.
public actor ClaudeIntentResolver: IntentResolving {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let requestTimeout: TimeInterval = 4
    static let bodyPrefixLimit = 200

    private let config: AppConfig
    private let session: URLSession
    private let baseURL: URL
    private let deadline: Duration

    /// `baseURL` and `deadline` exist for tests; production uses the defaults.
    public init(config: AppConfig, session: URLSession = .shared,
                baseURL: URL = ClaudeIntentResolver.endpoint,
                deadline: Duration = .milliseconds(4500)) {
        self.config = config
        self.session = session
        self.baseURL = baseURL
        self.deadline = deadline
    }

    public func resolve(_ transcript: String, context: IntentContext) async throws -> [Action] {
        guard let key = config.anthropicAPIKey, !key.isEmpty else { throw IntentError.noAPIKey }
        let builder = ClaudeRequestBuilder(model: config.intentModel, effort: config.intentEffort)
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.timeoutInterval = Self.requestTimeout
        for (name, value) in ClaudeRequestBuilder.headers(key) { request.setValue(value, forHTTPHeaderField: name) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try builder.body(transcript: transcript, context: context)
        } catch {
            throw IntentError.decode(.malformed("could not encode request"))
        }

        let (data, http) = try await IntentHTTP.send(request, session: session, deadline: deadline)
        if !(200..<300).contains(http.statusCode) {
            let text = String(decoding: data.prefix(Self.bodyPrefixLimit * 4), as: UTF8.self)
            throw IntentError.http(http.statusCode, String(text.prefix(Self.bodyPrefixLimit)))
        }
        do {
            return try IntentDecoder.actions(fromResponse: data)
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
}

public enum IntentContextBuilder {
    public static func make(elements: ElementProviding, mode: Mode, maxElements: Int = 60,
                            overlay: OverlayState = .none) -> IntentContext {
        makeBundle(elements: elements, mode: mode, maxElements: maxElements, overlay: overlay).context
    }

    /// `labels` holds only the elements actually listed in the context (titled, within `maxElements`).
    public static func makeBundle(elements: ElementProviding, mode: Mode, maxElements: Int = 60,
                                  overlay: OverlayState = .none) -> IntentContextBundle {
        let all = LabelAssigner.assign(elements.actionableElements())
        var out: [(number: Int, title: String)] = []
        var snapshot: [Int: UIElementInfo] = [:]
        for n in all.keys.sorted() {
            guard let e = all[n],
                  !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if out.count >= maxElements { break }
            out.append((number: n, title: e.title))
            snapshot[n] = e
        }
        let context = IntentContext(frontmostApp: elements.frontmostAppName() ?? "", mode: mode,
                                    labeledElements: out, overlay: overlay.kindName)
        return IntentContextBundle(context: context, labels: snapshot)
    }
}
