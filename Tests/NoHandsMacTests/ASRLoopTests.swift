import Testing
import Foundation
import NoHandsCore
@testable import NoHandsMac

/// Replies in call order and records how many samples each call got.
private actor ScriptedTranscriber: Transcribing {
    private var replies: [Result<String, Error>]
    private(set) var sampleCounts: [Int] = []
    init(_ replies: [Result<String, Error>]) { self.replies = replies }
    func transcribe(_ samples: [Float]) async throws -> String {
        sampleCounts.append(samples.count)
        return try replies.isEmpty ? "" : replies.removeFirst().get()
    }
}

private let chunk = 4096

private func job(_ kind: VoicePipeline.ASRJob.Kind, chunks: Int, voiced: Int, id: Int = 1) -> VoicePipeline.ASRJob {
    VoicePipeline.ASRJob(kind: kind, segment: UtteranceSegment(id: id, samples: [Float](repeating: 0.1, count: chunks * chunk),
                                                               voicedEnd: voiced * chunk), at: .now, voiceEnd: nil)
}

/// Runs `jobs` through the ASR loop into a command-mode MergeBuffer built like the pipeline's; returns what it emitted
/// and the sample counts the transcriber was given.
private func drive(_ jobs: [VoicePipeline.ASRJob], replies: [Result<String, Error>]) async throws -> (emitted: [String], counts: [Int]) {
    let grammar = CommandGrammar()
    let (out, outCont) = AsyncStream<String>.makeStream(bufferingPolicy: .unbounded)
    let merge = MergeBuffer(
        merger: UtteranceMerger(windowMs: 20, unfinishedWindowMs: 20), gate: .off,
        isComplete: { VoicePipeline.isComplete($0, mode: $1, grammar: grammar) },
        carriesSpokenText: { VoicePipeline.carriesSpokenText($0, grammar: grammar) },
        onHold: { _ in }, emit: { text, _ in outCont.yield(text) })
    let (stream, cont) = AsyncStream<VoicePipeline.ASRJob>.makeStream(bufferingPolicy: .unbounded)
    for j in jobs { cont.yield(j) }
    cont.finish()
    let t = ScriptedTranscriber(replies)
    await VoicePipeline.runASR(stream, transcriber: t, merge: merge)
    try await Task.sleep(for: .milliseconds(150))      // past the merge window, for text that is not released at once
    outCont.finish()
    var emitted: [String] = []
    for await text in out { emitted.append(text) }
    return (emitted, await t.sampleCounts)
}

@Test func afterAnEarlyCloseOnlyNewVoicedAudioIsTranscribed() async throws {
    // The early pass heard 2 chunks and "new tab" ran. The full segment is 6 chunks long.
    let table: [(name: String, lateVoicedTo: Int, late: String, emitted: [String], counts: [Int])] = [
        ("noise only: no voiced chunk after the close", 1, "go back", ["new tab"], [2 * chunk]),
        ("stop said after the command still halts", 5, "stop", ["new tab", "stop"], [2 * chunk, 4 * chunk]),
        ("words after the command are their own utterance", 5, "scroll down", ["new tab", "scroll down"], [2 * chunk, 4 * chunk]),
    ]
    for row in table {
        let r = try await drive([job(.early, chunks: 2, voiced: 1), job(.full, chunks: 6, voiced: row.lateVoicedTo)],
                                replies: [.success("new tab"), .success(row.late)])
        #expect(r.emitted == row.emitted, "\(row.name)")
        #expect(r.counts == row.counts, "\(row.name)")
    }
}

@Test func anEarlyPassThatDoesNotCloseLeavesTheFullPassWholeAndAudible() async throws {
    let early: [(name: String, reply: Result<String, Error>)] = [
        ("throws", .failure(Boom())), ("hears nothing", .success("")), ("does not parse", .success("make it")),
        ("is free text", .success("type hello")),
    ]
    for row in early {
        let r = try await drive([job(.early, chunks: 2, voiced: 2), job(.full, chunks: 4, voiced: 4)],
                                replies: [row.reply, .success("go back")])
        #expect(r.emitted == ["go back"], "\(row.name)")
        #expect(r.counts == [2 * chunk, 4 * chunk], "\(row.name)")      // the full pass got the whole utterance
    }
}

@Test func earlyPassesAreSkippedWithoutVoiceOrPastFourSeconds() async throws {
    let long = 4 * 16_000 / chunk + 2     // just over 4 s of audio
    let r = try await drive([job(.early, chunks: 3, voiced: 0), job(.early, chunks: long, voiced: long),
                             job(.full, chunks: 3, voiced: 3)], replies: [.success("go back")])
    #expect(r.counts == [3 * chunk])      // only the full pass ran
    #expect(r.emitted == ["go back"])
}
