import Foundation
import NoHandsCore

public enum IntentError: Error {
    case noAPIKey
    case network(Error)
    case http(Int, String)
    case decode(IntentDecodeError)
    case timeout
    case cancelled
}

/// Refuses every redirect so the x-api-key header can never be forwarded to another host.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
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
        let builder = ClaudeRequestBuilder(model: config.intentModel)
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

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await send(request)
        } catch let e as IntentError {
            throw e
        } catch is CancellationError {
            throw IntentError.cancelled
        } catch let e as URLError where e.code == .cancelled {
            throw IntentError.cancelled
        } catch let e as URLError where e.code == .timedOut {
            throw IntentError.timeout
        } catch {
            throw IntentError.network(Self.scrubbed(error))
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let text = String(decoding: data.prefix(Self.bodyPrefixLimit * 4), as: UTF8.self)
            throw IntentError.http(http.statusCode, String(text.prefix(Self.bodyPrefixLimit)))
        }
        do {
            return try IntentDecoder.actions(fromResponse: data)
        } catch let e as IntentDecodeError {
            throw IntentError.decode(e)
        }
    }

    /// Races the request against a hard deadline; the loser is cancelled.
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let session = self.session
        let deadline = self.deadline
        return try await withThrowingTaskGroup(of: (Data, URLResponse)?.self) { group in
            group.addTask { try await session.data(for: request, delegate: NoRedirectDelegate()) }
            group.addTask { try await Task.sleep(for: deadline); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw IntentError.timeout }
            guard let result = first else { throw IntentError.timeout }
            return result
        }
    }

    /// Keep only domain/code of the underlying error so no request details can leak.
    private static func scrubbed(_ error: Error) -> Error {
        let ns = error as NSError
        return NSError(domain: ns.domain, code: ns.code)
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
