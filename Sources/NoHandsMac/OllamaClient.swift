import Foundation
import NoHandsCore

/// Talks only to the configured (loopback) Ollama base URL: status, model download, warm-up.
public actor OllamaClient {
    public struct PullError: Error, Equatable, Sendable { public let message: String }

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public static func installedAppURL() -> URL? {
        let fm = FileManager.default
        let candidates = [URL(fileURLWithPath: "/Applications/Ollama.app"),
                          fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Ollama.app")]
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    /// `.notRunning`, `.modelMissing` or `.ready` only.
    public func status(model: String) async -> LocalModelStatus {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/tags"), timeoutInterval: 2)
        req.httpMethod = "GET"
        guard let (data, resp) = try? await session.data(for: req, delegate: NoRedirectDelegate()),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return .notRunning }
        let names = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["models"] as? [[String: Any]])?
            .compactMap { $0["name"] as? String } ?? []
        let wanted = model.contains(":") ? model : model + ":latest"
        return names.contains(wanted) ? .ready : .modelMissing
    }

    public func pull(model: String, progress: @Sendable (Double?) -> Void) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        req.httpMethod = "POST"
        req.timeoutInterval = 24 * 3600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true] as [String: Any])
        let (bytes, resp) = try await session.bytes(for: req, delegate: NoRedirectDelegate())
        if let code = (resp as? HTTPURLResponse)?.statusCode, !(200..<300).contains(code) {
            throw PullError(message: "HTTP \(code)")
        }
        for try await line in bytes.lines {
            switch PullEvent.parse(line: line) {
            case .progress(let p): progress(p)
            case .success: return
            case .error(let m): throw PullError(message: m)
            case nil: continue
            }
        }
        throw PullError(message: "stream ended before success")
    }

    /// Loads the model, keeps it resident, and prefills the fixed prompt prefix into Ollama's cache (one token is
    /// generated). Cold prefill of the prefix took 3-20 s on an M1 Pro under memory pressure; hence the long timeout.
    /// `harness` must match the harness tasks will run with: the cached prefix differs per harness.
    public func warm(model: String, harness: HarnessKind = .native) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: 120)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = OllamaRequestBuilder(model: model).warmBody(harness: harness)
        _ = try await session.data(for: req, delegate: NoRedirectDelegate())
    }
}
