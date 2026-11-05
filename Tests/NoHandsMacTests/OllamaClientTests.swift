import Testing
import Foundation
@testable import NoHandsMac
@testable import NoHandsCore

private final class Box<T>: @unchecked Sendable {
    private let lock = NSLock(); private var v: T
    init(_ v: T) { self.v = v }
    func mutate(_ f: (inout T) -> Void) { lock.lock(); f(&v); lock.unlock() }
    var value: T { lock.lock(); defer { lock.unlock() }; return v }
}

private let base = URL(string: "http://127.0.0.1:11434")!

// Extends the Claude suite (serialized) so all HTTP-stub tests share StubProtocol's static state without racing.
extension ClaudeIntentResolverTests {
    @Test func ollamaResolverReturnsContinueStep() async throws {
        let content = #"{"intent":"open menu","status":"continue","actions":[{"kind":"type_text","text":"hi"}]}"#
        let obj: [String: Any] = ["message": ["role": "assistant", "content": content]]
        StubProtocol.reset { _ in (200, try! JSONSerialization.data(withJSONObject: obj)) }
        let r = OllamaIntentResolver(config: AppConfig(), session: makeSession())
        let ctx = IntentContext(frontmostApp: "Safari", mode: .command, labeledElements: [(1, "Back")])
        let step = try await r.resolve(StepRequest(oneShot: "go", context: ctx))
        #expect(step == IntentStep(intent: "open menu", status: .continue, actions: [.typeText("hi")]))
    }

    @Test func ollamaStatusReflectsTags() async {
        StubProtocol.reset { r in
            #expect(r.url?.path == "/api/tags")
            return (200, Data(#"{"models":[{"name":"qwen2.5:7b-instruct"},{"name":"llama3.1:latest"}]}"#.utf8))
        }
        let c = OllamaClient(baseURL: base, session: makeSession())
        #expect(await c.status(model: "qwen2.5:7b-instruct") == .ready)
        #expect(await c.status(model: "llama3.1:8b") == .modelMissing)
        #expect(await c.status(model: "llama3.1") == .ready)
    }

    @Test func ollamaStatusConnectionFailureIsNotRunning() async {
        StubProtocol.reset(nil)
        StubProtocol.failWith = URLError(.cannotConnectToHost)
        let c = OllamaClient(baseURL: base, session: makeSession())
        #expect(await c.status(model: "qwen2.5:7b-instruct") == .notRunning)
    }

    @Test func ollamaPullErrorLineThrows() async {
        StubProtocol.reset { r in
            #expect(r.url?.path == "/api/pull")
            return (200, Data("{\"status\":\"downloading\",\"total\":200,\"completed\":100}\n{\"error\":\"disk full\"}\n".utf8))
        }
        let seen = Box<[Double?]>([])
        let c = OllamaClient(baseURL: base, session: makeSession())
        await #expect(throws: (any Error).self) {
            try await c.pull(model: "m") { p in seen.mutate { $0.append(p) } }
        }
        #expect(seen.value.first == .some(0.5))
    }

    @Test func ollamaPullWithoutSuccessThrows() async {
        StubProtocol.reset { _ in (200, Data("{\"status\":\"pulling manifest\"}\n".utf8)) }
        let c = OllamaClient(baseURL: base, session: makeSession())
        await #expect(throws: (any Error).self) { try await c.pull(model: "m") { _ in } }
    }

    @Test func ollamaPullSuccess() async throws {
        StubProtocol.reset { _ in
            (200, Data("{\"status\":\"pulling manifest\"}\n{\"status\":\"downloading\",\"total\":4,\"completed\":4}\n{\"status\":\"success\"}\n".utf8))
        }
        let c = OllamaClient(baseURL: base, session: makeSession())
        try await c.pull(model: "m") { _ in }
        let body = try JSONSerialization.jsonObject(with: StubProtocol.bodies[0]) as? [String: Any]
        #expect(body?["model"] as? String == "m")
        #expect(body?["stream"] as? Bool == true)
    }

    @Test func ollamaWarmPrefillsThePromptPrefix() async throws {
        StubProtocol.reset { _ in (200, Data("{}".utf8)) }
        let c = OllamaClient(baseURL: base, session: makeSession())
        try await c.warm(model: "m")
        let req = try #require(StubProtocol.requests.first)
        #expect(req.url?.path == "/api/chat")
        #expect(req.timeoutInterval >= 120)
        let body = try JSONSerialization.jsonObject(with: StubProtocol.bodies[0]) as? NSDictionary
        let expected = try JSONSerialization.jsonObject(with: OllamaRequestBuilder(model: "m").warmBody()) as? NSDictionary
        #expect(body == expected)
    }
}
