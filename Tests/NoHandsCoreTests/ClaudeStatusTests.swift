import Testing
import Foundation
@testable import NoHandsCore

private let key = "sk-ant-api03-SECRETKEYSECRETKEY-1234567890"

private func config(_ backend: IntentBackend, key: String?, env: Bool = false) throws -> AppConfig {
    let json = #"{"intentBackend":"\#(backend.rawValue)"\#(key.map { #","anthropicAPIKey":"\#($0)""# } ?? "")}"#
    return try AppConfig.load(from: Data(json.utf8), environment: env ? ["ANTHROPIC_API_KEY": key ?? ""] : [:])
}

@Test func plainStatusLineFollowsBackendAndKey() throws {
    let table: [(IntentBackend, String?, Bool, String)] = [
        (.auto, key, false, "Claude: key set (config.json)"),
        (.claude, key, false, "Claude: key set (config.json)"),
        (.auto, key, true, "Claude: key set (ANTHROPIC_API_KEY)"),
        (.auto, nil, false, "Claude: no key, using the local model"),
        (.claude, nil, false, "Claude: no key, LLM off (add anthropicAPIKey)"),
        (.local, key, false, "Claude: not used (intentBackend = local)"),
        (.local, nil, false, "Claude: not used (intentBackend = local)"),
        (.off, key, false, "Claude: not used (intentBackend = off)"),
    ]
    for (backend, k, env, line) in table {
        #expect(ClaudeStatus.plainLine(try config(backend, key: k, env: env)) == line, "\(backend) \(k ?? "nil") \(env)")
    }
    var noSource = AppConfig(); noSource.anthropicAPIKey = key
    #expect(ClaudeStatus.plainLine(noSource) == "Claude: key set")
    // A result replaces the plain line; checking replaces both; no key has no result text.
    let cfg = try config(.local, key: key)
    let ok = ClaudeCheckResult(kind: .connected, statusCode: 200)
    #expect(ClaudeStatus.menuLine(config: cfg, checking: false, last: (ok, "14:32")) == "Claude: connected at 14:32")
    #expect(ClaudeStatus.menuLine(config: cfg, checking: true, last: (ok, "14:32")) == "Claude: checking…")
    #expect(ClaudeStatus.menuLine(config: cfg, checking: false, last: (.noKey, "14:32")) == ClaudeStatus.plainLine(cfg))
}

private func apiError(_ type: String, _ message: String) -> Data {
    try! JSONSerialization.data(withJSONObject: ["type": "error", "error": ["type": type, "message": message]])
}

@Test func statusAndBodyBecomeResultAndText() {
    let schema = apiError("invalid_request_error", "Schemas contains too many optional parameters (32), which would make grammar compilation inefficient.")
    let table: [(Int, Data, ClaudeCheckKind, String?)] = [
        (200, Data("{}".utf8), .connected, "Claude: connected at 14:32"),
        (400, schema, .requestRejected,
         "Claude: request rejected at 14:32: invalid_request_error: Schemas contains too many optional parameters ("),
        (400, Data("<html>bad gateway</html>".utf8), .requestRejected, "Claude: request rejected at 14:32"),
        (401, apiError("authentication_error", "invalid x-api-key"), .keyRejected, "Claude: key rejected at 14:32, check anthropicAPIKey"),
        (403, Data(), .keyRejected, "Claude: key rejected at 14:32, check anthropicAPIKey"),
        (404, apiError("not_found_error", "model: x"), .modelNotFound, "Claude: model not found at 14:32, check intentModel"),
        (429, Data(), .rateLimited, "Claude: rate limited at 14:32, try again soon"),
        (529, Data(), .unavailable(529), "Claude: unavailable at 14:32 (HTTP 529), try again later"),
        (302, Data(), .unavailable(302), "Claude: unavailable at 14:32 (HTTP 302), try again later"),
    ]
    for (status, body, kind, text) in table {
        let r = ClaudeCheckResult.from(status: status, body: body, apiKey: key)
        #expect(r.kind == kind && r.statusCode == status, "\(status)")
        #expect(r.menuText(at: "14:32") == text, "\(status)")
    }
    #expect(ClaudeCheckResult.timedOut.menuText(at: "14:32") == "Claude: timed out at 14:32, check your connection")
    #expect(ClaudeCheckResult.noNetwork.menuText(at: "14:32") == "Claude: no network at 14:32, check your connection")
    #expect(ClaudeCheckResult.noKey.menuText(at: "14:32") == nil)
    let cli = ClaudeCheckResult.from(status: 400, body: schema, apiKey: key).cliText(model: "claude-haiku-5-5")
    #expect(cli.hasPrefix("Claude: request rejected (HTTP 400, model claude-haiku-5-5)\ninvalid_request_error: Schemas contains"))
}

@Test func detailNeverHoldsTheKeyOrControlCharacters() {
    let long = String(repeating: "a", count: 40)
    let cases: [(String, String)] = [
        ("bad key \(key) here", "plain echo"),
        ("\(String(repeating: "x", count: 55))\(key)", "key across the 70 cut"),
        ("\(String(repeating: "y", count: 480))\(key)", "key across the 500 cut"),
        ("\(long) sk-ant-oat01-OTHER_TOKEN-9 \(long)", "other sk-ant token"),
        ("ends with prefix sk-ant-", "bare prefix"),
        ("line one\n\u{1B}[31mred\u{1B}[0m\tand\u{7}  gaps", "control characters"),
    ]
    for (message, label) in cases {
        let r = ClaudeCheckResult.from(status: 400, body: apiError("invalid_request_error", message), apiKey: key)
        let shown = [r.detail, r.menuText(at: "14:32"), r.cliText(model: "m")].compactMap { $0 }.joined(separator: "\n")
        #expect(!shown.contains(key) && !shown.contains("sk-ant-") && !shown.contains("SECRETKEY"), "\(label)")
        #expect(r.detail.map { $0.count <= 500 } == true, "\(label)")
        #expect(!(r.detail ?? "").unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }, "\(label)")
    }
    // Only a JSON body of sane size gives a detail.
    let huge = apiError("invalid_request_error", String(repeating: "z", count: 70_000))
    #expect(ClaudeCheckResult.from(status: 400, body: huge, apiKey: key).detail == nil)
    #expect(ClaudeCheckResult.from(status: 500, body: Data("<html>\(key)</html>".utf8), apiKey: key).detail == nil)
}

@Test func connectionCheckBodyIsARealStepBodyWithOneToken() throws {
    func parse(_ d: Data) throws -> [String: Any] { try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any]) }
    for vision in [false, true] {
        let builder = ClaudeRequestBuilder(model: "claude-haiku-5-5", effort: "medium", vision: vision)
        let check = try parse(try builder.connectionCheckBody())
        let real = try parse(try builder.body(transcript: "open the downloads folder",
                                              context: IntentContext(frontmostApp: "Finder", mode: .command, labeledElements: [])))
        for field in ["output_config", "model", "system"] {
            #expect(NSDictionary(dictionary: [field: check[field] as Any]) == NSDictionary(dictionary: [field: real[field] as Any]), "\(field) vision=\(vision)")
        }
        #expect(check["max_tokens"] as? Int == 1 && real["max_tokens"] as? Int == 2048)
    }
}
