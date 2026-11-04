import Testing
import Foundation
@testable import NoHandsCore

@Test func configDefaultsAndEnvOverride() throws {
    let c = try AppConfig.load(from: nil, environment: [:])
    #expect(c.intentModel == "claude-opus-5-5"); #expect(c.silenceMs == 350); #expect(c.anthropicAPIKey == nil)
    let json = #"{"anthropicAPIKey":"file-key","silenceMs":500,"unknownKey":1}"#.data(using: .utf8)
    let d = try AppConfig.load(from: json, environment: ["ANTHROPIC_API_KEY": "env-key"])
    #expect(d.anthropicAPIKey == "env-key"); #expect(d.silenceMs == 500)
}

@Test func configClampsValues() throws {
    let json = #"{"gridColumns":0,"gridRows":999,"moveStepPx":-5,"scrollStepLines":500,"silenceMs":5}"#.data(using: .utf8)
    let c = try AppConfig.load(from: json, environment: [:])
    #expect(c.gridColumns == 1); #expect(c.gridRows == 40); #expect(c.moveStepPx == 1)
    #expect(c.scrollStepLines == 50); #expect(c.silenceMs == 100)
    #expect(c.grammarConfig.moveStepPx == 1)
}

@Test func configInvalidJSONThrows() {
    #expect(throws: (any Error).self) {
        try AppConfig.load(from: "not json".data(using: .utf8), environment: [:])
    }
}

@Test func backendSelection() throws {
    func cfg(_ json: String, env: [String: String] = [:]) throws -> AppConfig {
        try AppConfig.load(from: Data(json.utf8), environment: env)
    }
    #expect(try cfg("{}").effectiveBackend == .local)
    #expect(try cfg(#"{"anthropicAPIKey":"k"}"#).effectiveBackend == .claude)
    #expect(try cfg(#"{"anthropicAPIKey":"k","intentBackend":"local"}"#).effectiveBackend == .local)
    #expect(try cfg(#"{"intentBackend":"claude"}"#).effectiveBackend == .off)
    #expect(try cfg(#"{"intentBackend":"off","anthropicAPIKey":"k"}"#).effectiveBackend == .off)
    let typo = try cfg(#"{"intentBackend":"lokal","anthropicAPIKey":"k"}"#)   // must not throw
    #expect(typo.intentBackend == .auto && typo.anthropicAPIKey == "k")
}

@Test func ollamaURLIsLoopbackOnly() throws {
    func url(_ s: String) throws -> String {
        try AppConfig.load(from: Data(#"{"ollamaURL":"\#(s)"}"#.utf8), environment: [:]).ollamaBaseURL.absoluteString
    }
    #expect(try url("http://localhost:11500") == "http://localhost:11500")
    #expect(try url("http://[::1]:11434") == "http://[::1]:11434")
    #expect(try url("http://example.com:11434") == "http://127.0.0.1:11434")
    #expect(try url("https://127.0.0.1.evil.com") == "http://127.0.0.1:11434")
    #expect(try url("not a url") == "http://127.0.0.1:11434")
}

@Test func localModelDefaultsByMemory() throws {
    let gb: UInt64 = 1 << 30
    #expect(AppConfig.defaultLocalModel(physicalMemoryBytes: 16 * gb) == "qwen2.5:7b-instruct")
    #expect(AppConfig.defaultLocalModel(physicalMemoryBytes: 12 * gb) == "qwen2.5:7b-instruct")
    #expect(AppConfig.defaultLocalModel(physicalMemoryBytes: 8 * gb) == "qwen2.5:3b-instruct")
    let set = try AppConfig.load(from: Data(#"{"localModel":"llama3.1:8b"}"#.utf8), environment: [:])
    #expect(set.resolvedLocalModel == "llama3.1:8b")
}
