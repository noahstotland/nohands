import Testing
import Foundation
@testable import NoHandsCore

@Test func configDefaultsAndEnvOverride() throws {
    let c = try AppConfig.load(from: nil, environment: [:])
    #expect(c.intentModel == "claude-opus-5-5"); #expect(c.silenceMs == 1000); #expect(c.intentEffort == "medium"); #expect(c.mergeWindowMs == 500); #expect(c.anthropicAPIKey == nil)
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

@Test func taskConfigDefaultsAndClamps() throws {
    let d = try AppConfig.load(from: nil, environment: [:])
    #expect(d.maxTaskSteps == 12); #expect(d.llmDeadlineMs == 12000); #expect(d.settleMs == 3000); #expect(d.maxObservedElements == 120)
    let lo = try AppConfig.load(from: Data(#"{"maxTaskSteps":0,"llmDeadlineMs":1,"settleMs":-5,"maxObservedElements":1}"#.utf8), environment: [:])
    #expect(lo.maxTaskSteps == 1); #expect(lo.llmDeadlineMs == 2000); #expect(lo.settleMs == 0); #expect(lo.maxObservedElements == 10)
    let hi = try AppConfig.load(from: Data(#"{"maxTaskSteps":99,"llmDeadlineMs":999999,"settleMs":99999,"maxObservedElements":9999}"#.utf8), environment: [:])
    #expect(hi.maxTaskSteps == 30); #expect(hi.llmDeadlineMs == 60000); #expect(hi.settleMs == 10000); #expect(hi.maxObservedElements == 300)
    let ok = try AppConfig.load(from: Data(#"{"maxTaskSteps":5}"#.utf8), environment: [:])
    #expect(ok.maxTaskSteps == 5)
}

@Test func localBackendHasItsOwnDeadlineAndElementCap() throws {
    let d = try AppConfig.load(from: nil, environment: [:])
    #expect(d.localLlmDeadlineMs == 30000); #expect(d.localMaxObservedElements == 40)
    let lo = try AppConfig.load(from: Data(#"{"localLlmDeadlineMs":1,"localMaxObservedElements":1}"#.utf8), environment: [:])
    #expect(lo.localLlmDeadlineMs == 2000); #expect(lo.localMaxObservedElements == 10)
    let hi = try AppConfig.load(from: Data(#"{"localLlmDeadlineMs":999999,"localMaxObservedElements":9999}"#.utf8), environment: [:])
    #expect(hi.localLlmDeadlineMs == 120000); #expect(hi.localMaxObservedElements == 300)

    // Without a key the backend is local: the local limits apply. With a key (Claude) the general ones do.
    let local = try AppConfig.load(from: Data(#"{"llmDeadlineMs":5000,"maxObservedElements":200}"#.utf8), environment: [:])
    #expect(local.effectiveBackend == .local)
    #expect(local.observedElementCap == 40)
    let claude = try AppConfig.load(from: Data(#"{"llmDeadlineMs":5000,"maxObservedElements":200}"#.utf8), environment: ["ANTHROPIC_API_KEY": "k"])
    #expect(claude.effectiveBackend == .claude)
    #expect(claude.observedElementCap == 200)
}

@Test func harnessConfigDefaultsDecodingAndClamps() throws {
    let d = try AppConfig.load(from: nil, environment: [:])
    #expect(d.desktopHarness == .auto && d.agentDesktopPath == nil && d.agentDesktopTimeoutMs == 8000)
    #expect(d.agentDesktopSnapshotMs == 3000 && d.agentDesktopHeadedFallback && !d.agentDesktopTrace)
    let c = try AppConfig.load(from: Data(#"{"desktopHarness":"agentDesktop","agentDesktopPath":"/x/agent-desktop","agentDesktopTimeoutMs":10,"agentDesktopSnapshotMs":99999,"agentDesktopHeadedFallback":false,"agentDesktopTrace":true}"#.utf8), environment: [:])
    #expect(c.desktopHarness == .agentDesktop && c.agentDesktopPath == "/x/agent-desktop")
    #expect(c.agentDesktopTimeoutMs == 1000 && c.agentDesktopSnapshotMs == 10000 && !c.agentDesktopHeadedFallback && c.agentDesktopTrace)
    let unknown = try AppConfig.load(from: Data(#"{"desktopHarness":"robot"}"#.utf8), environment: [:])
    #expect(unknown.desktopHarness == .auto)
    #expect(try AppConfig.load(from: Data(#"{"desktopHarness":"native"}"#.utf8), environment: [:]).desktopHarness == .native)
}

@Test func echoCancellationDefaultsOnAndParses() throws {
    #expect(try AppConfig.load(from: nil, environment: [:]).echoCancellation)
    #expect(try AppConfig.load(from: Data(#"{"silenceMs":600}"#.utf8), environment: [:]).echoCancellation)
    #expect(!(try AppConfig.load(from: Data(#"{"echoCancellation":false}"#.utf8), environment: [:]).echoCancellation))
}

@Test func attentionWordDefaultsOffAndIsNormalized() throws {
    #expect(try AppConfig.load(from: nil, environment: [:]).attentionWord == "")
    #expect(!(try AppConfig.load(from: nil, environment: [:])).attentionGate.isOn)
    let table: [(String, String)] = [
        (#"{"attentionWord":" Hey, Mac! "}"#, "hey mac"),
        (#"{"attentionWord":null}"#, ""),
        (#"{"attentionWord":"stop"}"#, ""),
        (#"{"attentionWord":"one two three four"}"#, ""),
    ]
    for (json, expected) in table {
        let c = try AppConfig.load(from: Data(json.utf8), environment: [:])
        #expect(c.attentionWord == expected, "\(json)")
        #expect(c.attentionGate.isOn == !expected.isEmpty, "\(json)")
    }
    #expect(throws: (any Error).self) { try AppConfig.load(from: Data(#"{"attentionWord":5}"#.utf8), environment: [:]) }
}

@Test func earlySilenceDefaultsAndClamps() throws {
    let table: [(String?, Int)] = [(nil, 350), (#"{"silenceMs":600}"#, 350), (#"{"earlySilenceMs":0}"#, 0),
                                   (#"{"earlySilenceMs":-5}"#, 0), (#"{"earlySilenceMs":99999}"#, 3000), (#"{"earlySilenceMs":500}"#, 500)]
    for (json, expected) in table {
        #expect(try AppConfig.load(from: json.map { Data($0.utf8) }, environment: [:]).earlySilenceMs == expected, "\(json ?? "nil")")
    }
}
