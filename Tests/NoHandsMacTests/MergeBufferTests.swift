import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

private final class Sink: @unchecked Sendable {
    let lock = NSLock()
    var emitted: [String] = []
    var held: [String] = []
    func emit(_ s: String) { lock.lock(); emitted.append(s); lock.unlock() }
    func hold(_ s: String) { lock.lock(); held.append(s); lock.unlock() }
    var out: [String] { lock.lock(); defer { lock.unlock() }; return emitted }
}

private func make(_ sink: Sink, window: Int = 80, unfinished: Int = 200) -> MergeBuffer {
    let grammar = CommandGrammar()
    return MergeBuffer(
        merger: UtteranceMerger(windowMs: window, unfinishedWindowMs: unfinished),
        isComplete: { VoicePipeline.isComplete($0, mode: $1, grammar: grammar) },
        onHold: { sink.hold($0) },
        emit: { text, _ in sink.emit(text) })
}

@Test func grammarCommandIsReleasedImmediately() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("go back", trace: LatencyTrace())
    #expect(sink.out == ["go back"])
    #expect(sink.held.isEmpty)
}

@Test func nonGrammarPhraseWaitsForTheWindow() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("make it bigger please", trace: LatencyTrace())
    #expect(sink.out.isEmpty)
    #expect(sink.held == ["make it bigger please"])
    try await Task.sleep(for: .milliseconds(250))
    #expect(sink.out == ["make it bigger please"])
}

@Test func speechResumingInsideTheWindowMergesBothHalves() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("click the", trace: LatencyTrace())
    try await Task.sleep(for: .milliseconds(100))
    await b.speechStarted()
    try await Task.sleep(for: .milliseconds(300))      // past the unfinished window: still waiting for ASR
    #expect(sink.out.isEmpty)
    await b.transcript("back button", trace: LatencyTrace())
    try await Task.sleep(for: .milliseconds(200))
    #expect(sink.out == ["click the back button"])
}

@Test func abandonedSpeechResumesTheWindow() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("hello there", trace: LatencyTrace())
    await b.speechStarted()
    await b.speechAbandoned()
    try await Task.sleep(for: .milliseconds(200))
    #expect(sink.out == ["hello there"])
}

@Test func resetDropsPending() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("hello there", trace: LatencyTrace())
    await b.reset()
    try await Task.sleep(for: .milliseconds(200))
    #expect(sink.out.isEmpty)
}

// MARK: - stop phrases and dictation escapes are never merged

@Test func stopPhraseIsReleasedImmediatelyInAnyMode() async {
    for mode in [Mode.command, .dictation, .sleep] {
        let sink = Sink()
        let b = make(sink)
        await b.set(mode: mode)
        await b.transcript("Stop, stop!", trace: LatencyTrace())
        #expect(sink.out == ["Stop, stop!"], "\(mode)")
        #expect(sink.held.isEmpty)
    }
}

@Test func stopAfterPendingTextDropsItInCommandMode() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("open the", trace: LatencyTrace())          // dangling: held for the long window
    await b.speechStarted()
    await b.transcript("stop", trace: LatencyTrace())
    #expect(sink.out == ["stop"])                                   // never "open the stop"
    try await Task.sleep(for: .milliseconds(300))
    #expect(sink.out == ["stop"])                                   // the dropped text never fires later
}

@Test func stopAfterPendingDictationKeepsTheDictatedWords() async {
    let sink = Sink()
    let b = make(sink)
    await b.set(mode: .dictation)
    await b.transcript("hello there", trace: LatencyTrace())
    await b.transcript("stop", trace: LatencyTrace())
    #expect(sink.out == ["hello there", "stop"])
}

@Test func dictationEscapeIsNeverMergedIntoDictatedText() async {
    let sink = Sink()
    let b = make(sink)
    await b.set(mode: .dictation)
    await b.transcript("stop dictating", trace: LatencyTrace())
    #expect(sink.out == ["stop dictating"])                         // released at once
    await b.transcript("hello there", trace: LatencyTrace())
    await b.transcript("command mode", trace: LatencyTrace())
    #expect(sink.out == ["stop dictating", "hello there", "command mode"])
}

@Test func scratchThatAfterPendingDictationFlushesTheFragmentFirst() async {
    let sink = Sink()
    let b = make(sink)
    await b.set(mode: .dictation)
    await b.transcript("hello there", trace: LatencyTrace())
    await b.transcript("scratch that", trace: LatencyTrace())
    #expect(sink.out == ["hello there", "scratch that"])             // not "hello there scratch that"
}

@Test func isCompleteCoversStopsAndDictationEscapes() {
    let g = CommandGrammar()
    #expect(VoicePipeline.isComplete("stop stop", mode: .command, grammar: g))
    #expect(VoicePipeline.isComplete("no stop", mode: .dictation, grammar: g))
    #expect(VoicePipeline.isComplete("go back", mode: .command, grammar: g))
    #expect(!VoicePipeline.isComplete("go back", mode: .dictation, grammar: g))
    #expect(VoicePipeline.isComplete("Stop dictating.", mode: .dictation, grammar: g))
    #expect(VoicePipeline.isComplete("command mode", mode: .dictation, grammar: g))
    #expect(VoicePipeline.isComplete("Scratch that.", mode: .dictation, grammar: g))
    #expect(VoicePipeline.isComplete("delete word", mode: .dictation, grammar: g))
    #expect(!VoicePipeline.isComplete("scratch that", mode: .command, grammar: g))
    #expect(!VoicePipeline.isComplete("hello there", mode: .dictation, grammar: g))
    #expect(!VoicePipeline.isComplete("make it bigger", mode: .command, grammar: g))
}
