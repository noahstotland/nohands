import Foundation
import Testing
import NoHandsCore
@testable import NoHandsMac

@Test func intentErrorsMapToHudText() {
    #expect(PipelineText.hud(for: .cancelled) == nil)
    #expect(PipelineText.hud(for: .noAPIKey) == "LLM off: add anthropicAPIKey to ~/.config/nohands/config.json")
    #expect(PipelineText.hud(for: .timeout) == "timed out")
    #expect(PipelineText.hud(for: .network(URLError(.notConnectedToInternet))) == "no network")
    #expect(PipelineText.hud(for: .http(500, "x")) == "LLM error (500)")
}

@Test func routingSummaries() {
    #expect(PipelineText.summary(.ignore(reason: "sleeping")) == "ignore(sleeping)")
    #expect(PipelineText.summary(.resolveWithLLM("x")) == "llm")
    #expect(PipelineText.summary(.execute([.setMode(.sleep)])).hasPrefix("execute ["))
}

@Test func logLineFormat() {
    var t = LatencyTrace()
    let start = ContinuousClock.now
    t.speechEnd = start
    t.asrDone = start.advanced(by: .milliseconds(100))
    t.actionsDone = start.advanced(by: .milliseconds(150))
    #expect(PipelineText.logLine(trace: t, transcript: "click", summary: "llm") == "[asr=100ms total=150ms] click -> llm")
}

@Test func menuTranscriptTruncation() {
    #expect(PipelineText.truncated("short") == "short")
    let long = String(repeating: "a", count: 100)
    #expect(PipelineText.truncated(long).count == 60)
    #expect(PipelineText.truncated(long).hasSuffix("…"))
    #expect(PipelineText.truncated(String(repeating: "b", count: 60)).count == 60)
}

@Test func newErrorsHaveHudText() {
    #expect(PipelineText.hud(for: .localUnavailable) == PipelineText.localNotRunning)
    #expect(PipelineText.hud(for: .modelMissing) == PipelineText.localNotDownloaded)
    #expect(PipelineText.localNotRunning == "local model not running: start Ollama")
    #expect(PipelineText.localNotDownloaded == "local model not downloaded: see the NoHands menu")
    #expect(PipelineText.llmDisabled == "LLM off (intentBackend is off)")
}
