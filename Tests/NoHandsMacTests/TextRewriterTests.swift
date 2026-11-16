import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private func claudeAnswer(_ text: String) -> Data {
    let payload = String(decoding: try! JSONSerialization.data(withJSONObject: ["text": text]), as: UTF8.self)
    return try! JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": payload]],
                                                         "usage": ["input_tokens": 10, "output_tokens": 5]])
}

private func ollamaAnswer(_ text: String) -> Data {
    let payload = String(decoding: try! JSONSerialization.data(withJSONObject: ["text": text]), as: UTF8.self)
    return try! JSONSerialization.data(withJSONObject: ["message": ["content": payload]])
}

// Extends the Claude suite (serialized) so every test shares StubProtocol's static state without racing.
extension ClaudeIntentResolverTests {
    @Test func rewritersPostOneRequestToTheirBackendAndMapItsErrors() async throws {
        var config = AppConfig()
        config.anthropicAPIKey = "sk-test-key"
        let meter = ClaudeUsageMeter()
        let claude = ClaudeTextRewriter(config: config, session: makeSession(), meter: meter)
        let ollama = OllamaTextRewriter(config: config, session: makeSession())
        let how = RewriteInstruction.style(.shorter)

        StubProtocol.reset { _ in (200, claudeAnswer("Hi.")) }
        #expect(try await claude.rewrite("Hello there.", how) == "Hi.")
        let sent = try #require(StubProtocol.requests.first)
        #expect(sent.url == ClaudeIntentResolver.endpoint && sent.value(forHTTPHeaderField: "x-api-key") == "sk-test-key")
        #expect(!String(decoding: StubProtocol.bodies[0], as: UTF8.self).contains("sk-test-key"))   // the key is a header only
        #expect(meter.total.calls == 1 && meter.total.output == 5)

        StubProtocol.reset { _ in (200, ollamaAnswer("Hi.")) }
        #expect(try await ollama.rewrite("Hello there.", how) == "Hi.")
        let local = try #require(StubProtocol.requests.first)
        #expect(local.url?.absoluteString == "http://127.0.0.1:11434/api/chat" && local.value(forHTTPHeaderField: "x-api-key") == nil)

        // (response, expected error for each backend)
        let table: [(Int, Data, String)] = [(500, Data("{}".utf8), "http"), (200, Data("{}".utf8), "noAnswer")]
        for (status, body, error) in table {
            StubProtocol.reset { _ in (status, body) }
            for rewriter in [claude as any TextRewriting, ollama] {
                do { _ = try await rewriter.rewrite("Hello there.", how); Issue.record("expected \(error)") }
                catch IntentError.http(let code, _) { #expect(error == "http" && code == 500) }
                catch RewriteError.noAnswer { #expect(error == "noAnswer") }
                catch { Issue.record("wrong error \(error)") }
            }
        }
        var noKey = config; noKey.anthropicAPIKey = nil
        await #expect(throws: IntentError.self) { try await ClaudeTextRewriter(config: noKey, session: makeSession()).rewrite("a", how) }
    }
}
