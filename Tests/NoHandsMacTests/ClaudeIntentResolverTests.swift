import Testing
import Foundation
import CoreGraphics
import NoHandsCore
@testable import NoHandsMac

private let secretKey = "sk-ant-SECRET-KEY-123"

private func config(key: String? = secretKey) -> AppConfig {
    var c = AppConfig(); c.anthropicAPIKey = key; return c
}

private let ctx = IntentContext(frontmostApp: "Safari", mode: .command, labeledElements: [(1, "Back")])

private func okBody(_ actionsJSON: String) -> Data {
    let text = "{\"actions\":\(actionsJSON)}"
    let obj: [String: Any] = ["stop_reason": "end_turn", "content": [["type": "text", "text": text]]]
    return try! JSONSerialization.data(withJSONObject: obj)
}

@Suite(.serialized) struct ClaudeIntentResolverTests {
    @Test func redirectsAreRefused() async {
        StubProtocol.reset { _ in (302, Data("moved".utf8)) }
        StubProtocol.redirectTo = URL(string: "https://evil.example/steal")!
        let r = ClaudeIntentResolver(config: config(), session: makeSession())
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.http(let s, _) { #expect(s == 302) }
        catch { Issue.record("wrong error \(error)") }
        #expect(StubProtocol.requests.count == 1)
        #expect(StubProtocol.requests.first?.url?.host == "api.anthropic.com")
    }

    @Test func callerCancellationThrowsCancelled() async {
        StubProtocol.reset { _ in nil }
        let r = ClaudeIntentResolver(config: config(), session: makeSession(), deadline: .seconds(30))
        let task = Task { try await r.resolve("a", context: ctx) }
        try? await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do { _ = try await task.value; Issue.record("expected throw") }
        catch IntentError.cancelled {}
        catch { Issue.record("wrong error \(error)") }
    }

    @Test func customModelIsSent() async throws {
        StubProtocol.reset { _ in (200, okBody("[]")) }
        var c = config(); c.intentModel = "claude-haiku-5-5"
        _ = try await ClaudeIntentResolver(config: c, session: makeSession()).resolve("a", context: ctx)
        let obj = try JSONSerialization.jsonObject(with: try #require(StubProtocol.bodies.first)) as? [String: Any]
        #expect(obj?["model"] as? String == "claude-haiku-5-5")
    }

    @Test func fastResponseDoesNotWaitForDeadline() async throws {
        StubProtocol.reset { _ in (200, okBody("[]")) }
        let r = ClaudeIntentResolver(config: config(), session: makeSession(), deadline: .seconds(30))
        let t0 = ContinuousClock.now
        _ = try await r.resolve("a", context: ctx)
        #expect(t0.duration(to: .now) < .seconds(2))
    }

    @Test func successDecodesAndSendsRightRequest() async throws {
        StubProtocol.reset { _ in (200, okBody(#"[{"kind":"type_text","text":"hi"}]"#)) }
        let r = ClaudeIntentResolver(config: config(), session: makeSession())
        let actions = try await r.resolve("say hi", context: ctx)
        #expect(actions == [.typeText("hi")])
        let req = try #require(StubProtocol.requests.first)
        #expect(req.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(req.httpMethod == "POST")
        #expect(req.timeoutInterval == 4)
        #expect(req.value(forHTTPHeaderField: "x-api-key") == secretKey)
        #expect(req.value(forHTTPHeaderField: "anthropic-version") == "2026-10-21")
        #expect(req.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let expected = try ClaudeRequestBuilder(model: AppConfig().intentModel).body(transcript: "say hi", context: ctx)
        let sent = try JSONSerialization.jsonObject(with: try #require(StubProtocol.bodies.first)) as? NSDictionary
        let want = try JSONSerialization.jsonObject(with: expected) as? NSDictionary
        #expect(sent != nil && sent == want)
    }

    @Test(arguments: [401, 429, 500]) func httpErrorsCarryTruncatedBody(status: Int) async {
        let long = String(repeating: "x", count: 500)
        StubProtocol.reset { _ in (status, Data(long.utf8)) }
        let r = ClaudeIntentResolver(config: config(), session: makeSession())
        do {
            _ = try await r.resolve("a", context: ctx)
            Issue.record("expected throw")
        } catch IntentError.http(let s, let body) {
            #expect(s == status)
            #expect(body.count == 200)
            #expect(!String(describing: IntentError.http(s, body)).contains(secretKey))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func refusalAndMalformed() async {
        StubProtocol.reset { _ in (200, try! JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": []])) }
        let r = ClaudeIntentResolver(config: config(), session: makeSession())
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.decode(let e) { #expect(e == .refusal) }
        catch { Issue.record("wrong error \(error)") }

        StubProtocol.reset { _ in (200, Data("not json".utf8)) }
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.decode(.malformed) {}
        catch { Issue.record("wrong error \(error)") }
    }

    @Test func noKeyMakesNoRequest() async {
        StubProtocol.reset { _ in (200, Data()) }
        for key in [nil, ""] as [String?] {
            let r = ClaudeIntentResolver(config: config(key: key), session: makeSession())
            do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
            catch IntentError.noAPIKey {}
            catch { Issue.record("wrong error \(error)") }
        }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func hungConnectionTimesOutAtDeadline() async {
        StubProtocol.reset { _ in nil }
        let r = ClaudeIntentResolver(config: config(), session: makeSession(), deadline: .milliseconds(300))
        let t0 = ContinuousClock.now
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.timeout {}
        catch { Issue.record("wrong error \(error)") }
        #expect(t0.duration(to: .now) < .seconds(2))
    }

    @Test func networkErrorIsScrubbedAndKeyNeverLeaks() async {
        StubProtocol.reset { _ in (200, Data()) }
        let failing = URLSessionConfiguration.ephemeral
        failing.protocolClasses = [FailProtocol.self]
        let r = ClaudeIntentResolver(config: config(), session: URLSession(configuration: failing))
        do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
        catch IntentError.network(let e) {
            let d = String(describing: IntentError.network(e)) + "\(e)" + e.localizedDescription + String(describing: (e as NSError).userInfo)
            #expect(!d.contains(secretKey))
            #expect(!d.contains("leak.example"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func keyNeverAppearsInAnyErrorDescription() async {
        let cases: [(((URLRequest) -> (Int, Data)?)?, String?)] = [
            ({ _ in (401, Data("unauthorized".utf8)) }, secretKey),
            ({ _ in (200, Data("garbage".utf8)) }, secretKey),
            ({ _ in (200, try! JSONSerialization.data(withJSONObject: ["stop_reason": "refusal"])) }, secretKey),
            ({ _ in nil }, secretKey),
            (nil, nil),
        ]
        for (h, key) in cases {
            StubProtocol.reset(h)
            let r = ClaudeIntentResolver(config: config(key: key), session: makeSession(), deadline: .milliseconds(200))
            do { _ = try await r.resolve("a", context: ctx); Issue.record("expected throw") }
            catch {
                #expect(!String(describing: error).contains(secretKey))
                #expect(!"\(error)".contains(secretKey))
                #expect(!error.localizedDescription.contains(secretKey))
            }
        }
    }
}

private final class FailProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost, userInfo: [
            NSURLErrorFailingURLErrorKey: URL(string: "https://leak.example/?k=\(secretKey)")!,
            NSURLErrorFailingURLStringErrorKey: "https://leak.example/?k=\(secretKey)",
            "extra": secretKey])) }
    override func stopLoading() {}
}

private final class FakeProvider: ElementProviding, @unchecked Sendable {
    var elements: [UIElementInfo] = []
    var front: String?
    func actionableElements() -> [UIElementInfo] { elements }
    func screenRectsCG() -> [CGRect] { [] }
    func activate(appNamed: String) -> Bool { false }
    func frontmostAppName() -> String? { front }
}

@Suite struct IntentContextBuilderTests {
    private func el(_ i: Int, _ title: String) -> UIElementInfo {
        UIElementInfo(id: i, frame: CGRect(x: 0, y: i * 20, width: 10, height: 10), title: title, role: "AXButton")
    }

    @Test func capsAtSixtyInLabelOrder() {
        let p = FakeProvider(); p.front = "Safari"
        p.elements = (0..<100).reversed().map { el($0, "T\($0)") }   // scrambled input order
        let c = IntentContextBuilder.make(elements: p, mode: .command)
        #expect(c.frontmostApp == "Safari")
        #expect(c.mode == .command)
        #expect(c.labeledElements.count == 60)
        #expect(c.labeledElements.map(\.number) == Array(1...60))
        #expect(c.labeledElements.first?.title == "T0")
    }

    @Test(arguments: [0, -3]) func nonPositiveCapReturnsNothing(cap: Int) {
        let p = FakeProvider(); p.elements = [el(0, "A"), el(1, "B")]
        #expect(IntentContextBuilder.make(elements: p, mode: .command, maxElements: cap).labeledElements.isEmpty)
    }

    @Test func skipsEmptyTitlesPreservingNumbers() {
        let p = FakeProvider()
        p.elements = [el(0, "A"), el(1, ""), el(2, "  "), el(3, "D")]
        let c = IntentContextBuilder.make(elements: p, mode: .dictation)
        #expect(c.frontmostApp == "")
        #expect(c.labeledElements.map(\.number) == [1, 4])
        #expect(c.labeledElements.map(\.title) == ["A", "D"])
    }
}
