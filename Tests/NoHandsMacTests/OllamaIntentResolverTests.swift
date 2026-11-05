import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private let ctx = IntentContext(frontmostApp: "Safari", mode: .command, labeledElements: [(1, "Back")])

private func chatBody(_ actionsJSON: String) -> Data {
    let content = "{\"actions\":\(actionsJSON)}"
    return try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])
}

// Extends the Claude suite (serialized) so both share StubProtocol's static state without racing.
extension ClaudeIntentResolverTests {
    @Test func postsChatAndDecodes() async throws {
        StubProtocol.reset { _ in (200, chatBody("[{\"kind\":\"show_grid\"}]")) }
        let r = OllamaIntentResolver(config: AppConfig(), session: makeSession())
        let actions = try await r.resolve("show grid", context: ctx)
        #expect(actions == [.showGrid])
        let req = try #require(StubProtocol.requests.first)
        #expect(req.url?.absoluteString == "http://127.0.0.1:11434/api/chat")
        #expect(req.httpMethod == "POST")
        #expect(req.value(forHTTPHeaderField: "x-api-key") == nil)
    }

    @Test func connectionRefusedMapsToLocalUnavailable() async {
        StubProtocol.reset { _ in nil }
        StubProtocol.failWith = URLError(.cannotConnectToHost)
        let r = OllamaIntentResolver(config: AppConfig(), session: makeSession())
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.localUnavailable {}
        catch { Issue.record("wrong error \(error)") }
    }

    @Test func missingModelMapsToModelMissing() async {
        StubProtocol.reset { _ in (404, Data("{\"error\":\"model \\\"qwen2.5:7b-instruct\\\" not found, try pulling it first\"}".utf8)) }
        let r = OllamaIntentResolver(config: AppConfig(), session: makeSession())
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.modelMissing {}
        catch { Issue.record("wrong error \(error)") }

        StubProtocol.reset { _ in (500, Data("{\"error\":\"boom\"}".utf8)) }
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.http(let code, _) { #expect(code == 500) }
        catch { Issue.record("wrong error \(error)") }
    }

    @Test func slowLocalModelTimesOut() async {
        StubProtocol.reset { _ in nil }
        let r = OllamaIntentResolver(config: AppConfig(), session: makeSession(), deadline: .milliseconds(200))
        let start = ContinuousClock.now
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.timeout {}
        catch { Issue.record("wrong error \(error)") }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func localResolverUsesTheLocalDeadline() async throws {
        StubProtocol.reset { _ in (200, chatBody("[{\"kind\":\"show_grid\"}]")) }
        let config = try AppConfig.load(from: Data(#"{"llmDeadlineMs":5000,"localLlmDeadlineMs":45000}"#.utf8), environment: [:])
        let r = OllamaIntentResolver(config: config, session: makeSession())
        _ = try await r.resolve("show grid", context: ctx)
        let req = try #require(StubProtocol.requests.first)
        #expect(req.timeoutInterval == 47)   // deadline + 2 s, so the URL loader never fires before the race does
    }
}
