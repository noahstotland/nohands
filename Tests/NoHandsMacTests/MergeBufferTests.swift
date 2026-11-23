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

/// Waits (at most 5 s, far under the buffer's 20 s safety timeout) for the sink to hold `expected`, so a slow
/// timer wake-up under load does not fail a test that is about *what* is released, not how fast.
private func waitForOutput(_ sink: Sink, _ expected: [String]) async {
    let start = ContinuousClock.now
    while sink.out != expected, start.duration(to: .now) < .seconds(5) { try? await Task.sleep(for: .milliseconds(10)) }
}

private func make(_ sink: Sink, window: Int = 80, unfinished: Int = 200, attention: AttentionGate = .off) -> MergeBuffer {
    let grammar = CommandGrammar()
    return MergeBuffer(
        merger: UtteranceMerger(windowMs: window, unfinishedWindowMs: unfinished),
        gate: attention,
        isComplete: { VoicePipeline.isComplete($0, mode: $1, grammar: grammar, attention: attention) },
        carriesSpokenText: { VoicePipeline.carriesSpokenText($0, grammar: grammar, attention: attention) },
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
    await waitForOutput(sink, ["make it bigger please"])
    #expect(sink.out == ["make it bigger please"])
}

@Test func speechResumingInsideTheWindowMergesBothHalves() async throws {
    let sink = Sink()
    let b = make(sink, unfinished: 5000)   // far past the test's own pauses; speech in progress holds it anyway
    await b.transcript("click the", trace: LatencyTrace())
    try await Task.sleep(for: .milliseconds(100))
    await b.speechStarted()
    try await Task.sleep(for: .milliseconds(300))      // speech in progress: still waiting for ASR
    #expect(sink.out.isEmpty)
    await b.transcript("back button", trace: LatencyTrace())
    await waitForOutput(sink, ["click the back button"])
    #expect(sink.out == ["click the back button"])
}

@Test func abandonedSpeechResumesTheWindow() async throws {
    let sink = Sink()
    let b = make(sink)
    await b.transcript("hello there", trace: LatencyTrace())
    await b.speechStarted()
    await b.speechAbandoned()
    await waitForOutput(sink, ["hello there"])
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
    #expect(!VoicePipeline.isComplete("spell kilo nine", mode: .command, grammar: g))   // waits so a pause can't split it
}

// MARK: - attention word

@Test func attentionWordKeepsStrayTextOutOfAddressedCommands() async throws {
    let gate = AttentionGate(configured: "computer")
    let sink = Sink()
    let b = make(sink, attention: gate)
    await b.transcript("hello there", trace: LatencyTrace())
    #expect(sink.held.isEmpty)                                      // stray text is held but shown nowhere
    await b.transcript("computer go back", trace: LatencyTrace())
    #expect(sink.out == ["hello there", "computer go back"])        // not merged; the command is released at once
    await b.transcript("computer, stop", trace: LatencyTrace())
    #expect(sink.out.last == "computer, stop")
    #expect(sink.held.isEmpty)
}

@Test func attentionWordAloneWaitsForTheRestOfTheCommand() async throws {
    let gate = AttentionGate(configured: "computer")
    let sink = Sink()
    let b = make(sink, window: 40, unfinished: 5000, attention: gate)
    await b.transcript("Computer.", trace: LatencyTrace())
    #expect(sink.held == ["Computer."])                             // shown as listening
    try await Task.sleep(for: .milliseconds(150))                   // past the normal window, inside the long one
    #expect(sink.out.isEmpty)
    await b.transcript("go back", trace: LatencyTrace())
    #expect(sink.out == ["Computer. go back"])
    #expect(VoicePipeline.isComplete("computer, go back", mode: .command, grammar: CommandGrammar(), attention: gate))
    #expect(!VoicePipeline.isComplete("go back", mode: .command, grammar: CommandGrammar(), attention: gate))
}

@Test func addressedSpellWaitsOutThePauseBetweenLetters() async throws {
    let gate = AttentionGate(configured: "computer")
    let sink = Sink()
    let b = make(sink, window: 40, unfinished: 1500, attention: gate)
    await b.transcript("Computer, spell kilo nine", trace: LatencyTrace())
    #expect(!VoicePipeline.isComplete("computer, spell kilo nine", mode: .command, grammar: CommandGrammar(), attention: gate))
    try await Task.sleep(for: .milliseconds(150))                   // past the normal window: still waiting
    #expect(sink.out.isEmpty)
    await b.transcript("alpha", trace: LatencyTrace())
    await waitForOutput(sink, ["Computer, spell kilo nine alpha"])
    #expect(sink.out == ["Computer, spell kilo nine alpha"])        // one phrase, so it types as one string
}

// MARK: - early pass

@Test func earlyTranscriptAcceptsOnlyWhatIsSafeToActOnNow() async throws {
    struct Row {
        var text: String
        var mode: Mode = .command
        var pending: String? = nil
        var attention = ""
        var window = 80
        var accepted: Bool
        var emitted: [String]
    }
    let rows = [
        Row(text: "new tab", accepted: true, emitted: ["new tab"]),
        Row(text: "scroll down", accepted: true, emitted: ["scroll down"]),
        Row(text: "click twelve", accepted: true, emitted: ["click twelve"]),           // numbered click
        Row(text: "stop", accepted: true, emitted: ["stop"]),
        Row(text: "type hello", accepted: false, emitted: []),                          // free text keeps the full window
        Row(text: "open youtube", accepted: false, emitted: []),
        Row(text: "go to example.com", accepted: false, emitted: []),
        Row(text: "click reload", accepted: false, emitted: []),
        Row(text: "click", accepted: false, emitted: []),                               // parses, but the last word dangles
        Row(text: "spell kilo nine", accepted: false, emitted: []),
        Row(text: "make it bigger", window: 0, accepted: false, emitted: []),           // not a command, even with no merge window
        Row(text: "go back", pending: "click the", accepted: false, emitted: []),       // a mid-way pause still merges
        Row(text: "stop", pending: "open the", accepted: true, emitted: ["stop"]),      // pending words are discarded, never merged
        Row(text: "go back", mode: .dictation, accepted: false, emitted: []),
        Row(text: "stop", mode: .dictation, accepted: false, emitted: []),
        Row(text: "stop", mode: .sleep, accepted: false, emitted: []),
        Row(text: "computer go back", attention: "computer", accepted: true, emitted: ["computer go back"]),
        Row(text: "go back", attention: "computer", accepted: false, emitted: []),
        Row(text: "computer click", attention: "computer", accepted: false, emitted: []),
        Row(text: "computer stop", attention: "computer", accepted: true, emitted: ["computer stop"]),
    ]
    for row in rows {
        let sink = Sink()
        let b = make(sink, window: row.window, unfinished: 5000, attention: AttentionGate(configured: row.attention))
        await b.set(mode: row.mode)
        if let pending = row.pending {
            await b.transcript(pending, trace: LatencyTrace())
            await b.speechStarted()
        }
        let accepted = await b.earlyTranscript(row.text, trace: LatencyTrace())
        #expect(accepted == row.accepted, "\(row.text) \(row.mode)")
        #expect(sink.out == row.emitted, "\(row.text) \(row.mode)")
    }
}

@Test func earlyPassIsWantedOnlyInCommandMode() async {
    let b = make(Sink())
    for (mode, wanted) in [(Mode.command, true), (.dictation, false), (.sleep, false)] {
        await b.set(mode: mode)
        #expect(await b.wantsEarlyPass == wanted, "\(mode)")
    }
}
