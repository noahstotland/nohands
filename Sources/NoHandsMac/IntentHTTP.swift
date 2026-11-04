import Foundation

/// Refuses every redirect so request headers can never be forwarded to another host.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// One request, no retries, raced against a hard deadline. Shared by the Claude and Ollama resolvers.
/// Non-2xx responses are returned to the caller, not thrown.
enum IntentHTTP {
    static func send(_ request: URLRequest, session: URLSession,
                     deadline: Duration) async throws(IntentError) -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await race(request, session: session, deadline: deadline)
            guard let http = response as? HTTPURLResponse else {
                throw IntentError.network(NSError(domain: "NoHands.IntentHTTP", code: 0))
            }
            return (data, http)
        } catch let e as IntentError {
            throw e
        } catch is CancellationError {
            throw .cancelled
        } catch let e as URLError where e.code == .cancelled {
            throw .cancelled
        } catch let e as URLError where e.code == .timedOut {
            throw .timeout
        } catch {
            throw .network(scrubbed(error))
        }
    }

    /// Races the request against the deadline; the loser is cancelled.
    private static func race(_ request: URLRequest, session: URLSession,
                             deadline: Duration) async throws -> (Data, URLResponse) {
        try await withThrowingTaskGroup(of: (Data, URLResponse)?.self) { group in
            group.addTask { try await session.data(for: request, delegate: NoRedirectDelegate()) }
            group.addTask { try await Task.sleep(for: deadline); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw IntentError.timeout }
            guard let result = first else { throw IntentError.timeout }
            return result
        }
    }

    /// Keep only domain/code of the underlying error so no request details can leak.
    static func scrubbed(_ error: Error) -> Error {
        let ns = error as NSError
        return NSError(domain: ns.domain, code: ns.code)
    }
}
