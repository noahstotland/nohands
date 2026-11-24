import Testing
import Foundation
@testable import NoHandsCore

@Test func configDefaultsAndEnvOverride() throws {
    let c = try AppConfig.load(from: nil, environment: [:])
    #expect(c.intentModel == "claude-haiku-5-5"); #expect(c.silenceMs == 1000); #expect(c.intentEffort == "low"); #expect(c.mergeWindowMs == 500); #expect(c.anthropicAPIKey == nil)
    let json = #"{"anthropicAPIKey":"file-key","silenceMs":500,"unknownKey":1}"#.data(using: .utf8)
    let d = try AppConfig.load(from: json, environment: ["ANTHROPIC_API_KEY": "env-key"])
    #expect(d.anthropicAPIKey == "env-key"); #expect(d.silenceMs == 500)
}

@Test func intentModelAndEffortDefaultsAndOverrides() throws {
    let table: [(String?, String, String)] = [
        (nil, "claude-haiku-5-5", "low"),
        ("{}", "claude-haiku-5-5", "low"),
        (#"{"intentModel":"claude-opus-5-5"}"#, "claude-opus-5-5", "low"),
        (#"{"intentEffort":"medium"}"#, "claude-haiku-5-5", "medium"),
        (#"{"intentEffort":"turbo"}"#, "claude-haiku-5-5", "low"),
    ]
    #expect(AppConfig().intentModel == "claude-haiku-5-5" && AppConfig().intentEffort == "low")
    for (json, model, effort) in table {
        let c = try AppConfig.load(from: json.map { Data($0.utf8) }, environment: [:])
        #expect(c.intentModel == model && c.intentEffort == effort, "\(json ?? "nil")")
    }
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

@Test func keySourceFollowsWhereTheKeyCameFrom() throws {
    let table: [(String?, [String: String], KeySource?)] = [
        (nil, [:], nil),
        (#"{"anthropicAPIKey":""}"#, [:], nil),
        (#"{"anthropicAPIKey":"f"}"#, [:], .file),
        (#"{"anthropicAPIKey":"f"}"#, ["ANTHROPIC_API_KEY": "e"], .environment),
        (nil, ["ANTHROPIC_API_KEY": "e"], .environment),
        (#"{"anthropicAPIKey":"f"}"#, ["ANTHROPIC_API_KEY": ""], .file),
    ]
    for (json, env, source) in table {
        let c = try AppConfig.load(from: json.map { Data($0.utf8) }, environment: env)
        #expect(c.anthropicKeySource == source, "\(json ?? "nil") \(env)")
    }
}

@Test func followUpWindowDefaultsAndClamps() throws {
    let table: [(String?, Int)] = [(nil, 30000), ("{}", 30000), (#"{"followUpWindowMs":0}"#, 0), (#"{"followUpWindowMs":-5}"#, 0),
                                   (#"{"followUpWindowMs":5000}"#, 5000), (#"{"followUpWindowMs":999999}"#, 120000)]
    for (json, expected) in table {
        #expect(try AppConfig.load(from: json.map { Data($0.utf8) }, environment: [:]).followUpWindowMs == expected, "\(json ?? "nil")")
    }
}

@Test func vocabularyEntriesAreCleanedAndCounted() throws {
    let many = (0..<203).map { #"{"hear":"w\#($0)","say":"W"}"# }.joined(separator: ",")
    let table: [(json: String, kept: [Vocabulary.Entry], skipped: Int)] = [
        (#"{}"#, [], 0),
        (#"{"vocabulary":"raptures"}"#, [], 1),
        (#"{"vocabulary":[{"hear":"raptures","say":"Raptors"}]}"#, [.init(hear: ["raptures"], say: "Raptors")], 0),
        (#"{"vocabulary":[{"hear":["a b","c"],"say":"X"}]}"#, [.init(hear: ["a b", "c"], say: "X")], 0),
        (#"{"vocabulary":[{"hear":"x"},{"say":"X"},{"hear":"x","say":""},{"hear":5,"say":"X"},7]}"#, [], 5),
        (#"{"vocabulary":[{"hear":"stop it","say":"X"},{"hear":"x","say":"never mind"},{"hear":"x","say":"Cancel"}]}"#, [], 3),
        (#"{"vocabulary":[{"hear":["halt","one","a b c d e f"],"say":"X"}]}"#, [.init(hear: ["one"], say: "X")], 0),
        (#"{"vocabulary":[{"hear":"x","say":"\#(String(repeating: "y", count: 101))"}]}"#, [], 1),
        (#"{"vocabulary":[{"hear":"x","say":"a\nb"},{"hear":"x","say":"a\tb"},{"hear":"x","say":"a\u001bb"},{"hear":"x","say":"a\u0085b"}]}"#, [], 4),
        (#"{"vocabulary":[{"hear":"x","say":"\n Raptors\t"},{"hear":"y","say":"👨‍👩‍👧"}]}"#, [.init(hear: ["x"], say: "Raptors"), .init(hear: ["y"], say: "👨‍👩‍👧")], 0),
        (#"{"vocabulary":[{"hear":["stop",\#((1...12).map { "\"s\($0)\"" }.joined(separator: ","))],"say":"X"}]}"#, [.init(hear: (1...10).map { "s\($0)" }, say: "X")], 0),
        (#"{"vocabulary":[\#(many)]}"#, (0..<200).map { .init(hear: ["w\($0)"], say: "W") }, 3),
    ]
    for row in table {
        let v = try AppConfig.load(from: Data(row.json.utf8), environment: [:]).vocabulary
        #expect(v.entries == row.kept, "\(row.json.prefix(80))")
        #expect(v.skipped == row.skipped, "\(row.json.prefix(80))")
    }
}

@Test func macrosDecodeAndABadValueNeverFailsTheConfig() throws {
    let table: [(json: String, kept: Int, skipped: Int)] = [
        (#"{}"#, 0, 0), (#"{"macros":{"night game":["click"]}}"#, 1, 0),
        (#"{"macros":["click"]}"#, 0, 1), (#"{"macros":"night game"}"#, 0, 1),
    ]
    for row in table {
        let c = try AppConfig.load(from: Data(row.json.utf8), environment: [:])
        #expect(c.macros.all.count == row.kept && c.macros.skipped == row.skipped, "\(row.json)")
    }
    #expect(try AppConfig.load(from: Data(#"{"macros":7,"silenceMs":500}"#.utf8), environment: [:]).silenceMs == 500)
}

@Test func routeMemoryIsOnUnlessTheConfigSaysFalse() throws {
    let table: [(String?, Bool)] = [(nil, true), ("{}", true), (#"{"routeMemory":false}"#, false), (#"{"routeMemory":true}"#, true),
                                    (#"{"routeMemory":"no"}"#, true), (#"{"routeMemory":0}"#, true), (#"{"routeMemory":null}"#, true)]
    for (json, expected) in table {
        #expect(try AppConfig.load(from: json.map { Data($0.utf8) }, environment: [:]).routeMemory == expected, "\(json ?? "nil")")
    }
}

@Test func commandLogIsOnUnlessTheConfigSaysFalse() throws {
    let table: [(String?, Bool)] = [(nil, true), (#"{"commandLog":false}"#, false), (#"{"commandLog":true}"#, true),
                                    (#"{"commandLog":"no"}"#, true), (#"{"commandLog":1}"#, true), (#"{"commandLog":null}"#, true)]
    for (json, expected) in table {
        #expect(try AppConfig.load(from: json.map { Data($0.utf8) }, environment: [:]).commandLog == expected, "\(json ?? "nil")")
    }
    #expect(try AppConfig.load(from: Data(#"{"commandLog":"no","silenceMs":500}"#.utf8), environment: [:]).silenceMs == 500)
    let patched = try AppConfig.load(from: CommandLogMenu.merged(existing: Data(#"{"silenceMs":500}"#.utf8), on: false), environment: [:])
    #expect(patched.silenceMs == 500 && !patched.commandLog)
}

@Test func packRegistryConfig() throws {
    let key = Data(repeating: 7, count: 32).base64EncodedString(), url = URL(string: "https://packs.example.org/i.json")!
    let table: [(String, PackRegistry.Setting, Int)] = [
        ("{}", .none, PackRegistry.defaultKeys.count),
        (#"{"packRegistryURL":""}"#, .off, 0),
        (#"{"packRegistryURL":"https://packs.example.org/i.json"}"#, .url(url), 0),
        (#"{"packRegistryURL":"https://packs.example.org/i.json","packRegistryKey":"\#(key)"}"#, .url(url), 1),
        (#"{"packRegistryURL":"http://packs.example.org/i.json","packRegistryKey":"\#(key)"}"#, .invalid("Registry URL must be https"), 0),
    ]
    for (json, setting, keys) in table {
        let c = try AppConfig.load(from: Data(json.utf8), environment: [:])
        #expect(c.packRegistry == setting && c.packRegistryTrustedKeys.count == keys, "\(json)")
    }
}
