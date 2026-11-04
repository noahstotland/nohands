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
        isComplete: { text, mode in mode == .command && grammar.parse(text) != nil },
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
