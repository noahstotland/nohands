import Testing
@testable import NoHandsCore

private let chunk = [Float](repeating: 0.1, count: 4096)      // 256 ms at 16 kHz
private let silence = [Float](repeating: 0, count: 4096)

@Test func assemblesSpeechWithPrePad() {
    var a = UtteranceAssembler(prePadMs: 256)
    #expect(a.push(silence, event: .none) == nil)
    #expect(a.push(chunk, event: .speechStart) == nil)
    #expect(a.push(chunk, event: .none) == nil)
    let u = a.push(chunk, event: .speechEnd)
    #expect(u?.count == 4 * 4096)          // 1 pre-pad chunk + 3 speech chunks
    #expect(u?.first == 0)                 // pre-pad came from the silence chunk
}

@Test func dropsTooShortUtterances() {
    var a = UtteranceAssembler(prePadMs: 0, minSpeechMs: 600)
    _ = a.push(chunk, event: .speechStart)
    #expect(a.push(chunk, event: .speechEnd) == nil)    // 512 ms < 600 ms
}

@Test func forcesCutAtMaxSpeech() {
    var a = UtteranceAssembler(prePadMs: 0, maxSpeechMs: 1000)
    _ = a.push(chunk, event: .speechStart)
    _ = a.push(chunk, event: .none)
    _ = a.push(chunk, event: .none)
    #expect(a.push(chunk, event: .none)?.count == 4 * 4096)   // 1024 ms ≥ 1000 ms
}

@Test func latencySummary() {
    var t = LatencyTrace()
    let now = ContinuousClock.now
    t.speechEnd = now; t.asrDone = now.advanced(by: .milliseconds(187)); t.actionsDone = now.advanced(by: .milliseconds(412))
    #expect(t.summary == "asr=187ms total=412ms")
}

@Test func continuesAfterForcedCut() {
    var a = UtteranceAssembler(prePadMs: 0, maxSpeechMs: 1000)
    _ = a.push(chunk, event: .speechStart)
    _ = a.push(chunk, event: .none)
    _ = a.push(chunk, event: .none)
    #expect(a.push(chunk, event: .none)?.count == 4 * 4096)
    _ = a.push(chunk, event: .none)
    #expect(a.push(chunk, event: .none) == nil)
    #expect(a.push(chunk, event: .speechEnd)?.count == 3 * 4096)
}

@Test func speechEndWithoutStartIsNil() {
    var a = UtteranceAssembler()
    #expect(a.push(chunk, event: .speechEnd) == nil)
}

@Test func duplicateSpeechStartIgnored() {
    var a = UtteranceAssembler(prePadMs: 0)
    _ = a.push(chunk, event: .speechStart)
    _ = a.push(chunk, event: .speechStart)
    #expect(a.push(chunk, event: .speechEnd)?.count == 3 * 4096)
}

@Test func prePadShorterThanRequested() {
    var a = UtteranceAssembler(prePadMs: 512)
    _ = a.push(silence, event: .none)
    _ = a.push(chunk, event: .speechStart)
    #expect(a.push(chunk, event: .speechEnd)?.count == 3 * 4096)
}

@Test func trailingSilenceDoesNotSatisfyMinSpeech() {
    var a = UtteranceAssembler(prePadMs: 0, minSpeechMs: 400)
    _ = a.push(chunk, event: .speechStart)
    _ = a.push(silence, event: .none)
    #expect(a.push(silence, event: .speechEnd) == nil)   // only 256 ms audible
}
