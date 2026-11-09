import Testing
@testable import NoHandsCore

private let voiced: Float = 0.95, quiet: Float = 0.05, between: Float = 0.78   // thresholds 0.85 / 0.70

@Test func earlySilenceDetectorFiresOncePerRun() {
    // (earlyMs, silenceMs, probabilities, chunk indices where it fires)
    let table: [(Int, Int, [Float], [Int])] = [
        (350, 1000, [voiced, quiet, quiet, quiet], [1]),                       // 1 chunk, once per run
        (512, 1000, [voiced, quiet, quiet, quiet], [2]),                       // 2 chunks
        (512, 1000, [voiced, quiet, voiced, quiet, quiet], [4]),               // voiced chunk resets the run
        (512, 1000, [voiced, quiet, voiced, quiet, quiet, voiced, quiet, quiet], [4, 7]),
        (512, 1000, [quiet, quiet, quiet], []),                                // silence before any speech
        (512, 1000, [voiced, between, between, between], []),                  // between thresholds never starts a run
        (512, 1000, [voiced, quiet, between, quiet], [2]),                     // ...and does not clear one
        (0, 1000, [voiced, quiet, quiet, quiet], []),                          // off
        (1000, 1000, [voiced, quiet, quiet, quiet], []),                       // not below the full window
    ]
    for (early, full, probs, expected) in table {
        var d = EarlySilenceDetector(earlySilenceMs: early, silenceMs: full)
        let fired = probs.indices.filter { d.feed(probability: probs[$0]) }
        #expect(fired == expected, "early \(early) full \(full) \(probs)")
    }
}

private let chunk = [Float](repeating: 0.1, count: 4096)

@Test func segmentIdsBumpOnEveryCloseAndSnapshotCarriesOffsets() {
    var a = UtteranceAssembler(prePadMs: 0, minSpeechMs: 400, maxSpeechMs: 1000)
    #expect(a.snapshot() == nil)
    _ = a.pushSegment(chunk, event: .speechStart)
    _ = a.pushSegment(chunk, event: .none, voiced: false)
    _ = a.pushSegment(chunk, event: .earlySilence, voiced: false)
    let snap = a.snapshot()
    #expect(snap?.samples.count == 3 * 4096); #expect(snap?.voicedEnd == 4096)
    let forced = a.pushSegment(chunk, event: .none)               // 1024 ms: forced cut, stays in speech
    #expect(forced?.id == snap?.id); #expect(a.snapshot()?.id == (snap?.id ?? 0) + 1)
    let dropped = a.pushSegment(chunk, event: .speechEnd, voiced: false)   // 256 ms of audio: dropped, id still bumps
    #expect(dropped == nil); #expect(a.snapshot() == nil)
    _ = a.pushSegment(chunk, event: .speechStart)
    #expect(a.snapshot()?.id == (snap?.id ?? 0) + 2)
}

@Test func earlyCloseLedgerTrimsAudio() {
    func seg(_ n: Int, voicedEnd: Int, id: Int = 1) -> UtteranceSegment {
        UtteranceSegment(id: id, samples: (0..<n).map(Float.init), voicedEnd: voicedEnd)
    }
    var ledger = EarlyCloseLedger(sampleRate: 100, maxEarlySeconds: 4)       // 400 samples
    #expect(ledger.audio(forEarly: seg(300, voicedEnd: 250))?.count == 300)
    #expect(ledger.audio(forEarly: seg(300, voicedEnd: 0)) == nil)           // no voice
    #expect(ledger.audio(forEarly: seg(401, voicedEnd: 400)) == nil)         // over 4 s
    ledger.recordEarlyClose(seg(300, voicedEnd: 250))
    let later = seg(500, voicedEnd: 450)
    #expect(ledger.audio(forEarly: later)?.first == 300)                     // only what came after
    #expect(ledger.audio(forEarly: seg(600, voicedEnd: 250)) == nil)         // noise after the close: nothing voiced
    #expect(ledger.audio(forFull: seg(600, voicedEnd: 250)) == nil)
    #expect(ledger.audio(forFull: later)?.count == 500)                      // the full close dropped the entry
}

@Test func freeTextPredicateOnGrammarPhrases() {
    let grammar = CommandGrammar()
    let table: [(String, Bool)] = [
        ("new tab", false), ("press command t", false), ("go back", false), ("scroll down", false),
        ("click 12", false), ("click", false), ("move left 20", false), ("show grid", false),
        ("type hello world", true), ("open youtube", true), ("open safari", true), ("go to example.org", true),
        ("go to cats", true), ("search for cats", true), ("search youtube for cats", true), ("click the back button", true),
    ]
    for (phrase, expected) in table {
        guard let actions = grammar.parse(phrase) else { Issue.record("\(phrase) should parse"); continue }
        #expect(actions.carriesSpokenText == expected, "\(phrase)")
    }
}
