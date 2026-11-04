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
