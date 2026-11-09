import Foundation
import NoHandsCore
import os

/// Replays one recording through the same pieces the live pipeline uses (VAD, assembler, early-close ledger, the ASR
/// loop and the merge buffer's early rule) so `nohands-cli endpoint-test` can measure early endpointing without a
/// microphone. The audio is fed in 4096-sample chunks paced to real time, so ASR and VAD overlap as they do live.
public enum EndpointReplay {
    public struct Report: Sendable {
        /// The true end of speech in the file (last 20 ms window with RMS above 0.005), in seconds.
        public var trueEnd: Double
        /// How many early passes were started, and the text of the accepted one, else of the first.
        public var earlyFired: Int
        public var earlyText: String?
        /// The early text was released to the pipeline (what the app would act on at ~350 ms).
        public var earlyAccepted: Bool
        /// Transcript of the whole utterance, as the full pass hears it with no early close.
        public var fullText: String?
        /// Early text and full text give the same actions (both stop phrases count as equal). nil when either is missing.
        public var sameAction: Bool?
        /// Accepted early close: true speech end to early text ready, in ms (audio time of the chunk that raised the
        /// early silence, minus the true end, plus the measured wall time of the early transcription).
        public var earlyReadyMs: Double?
        /// The same clock for the full path: true end to the closed utterance's text ready.
        public var fullReadyMs: Double?
        /// Transcripts released to the pipeline for this file; more than one means something extra would be acted on.
        public var emitted: [String]
    }

    private enum Event: Sendable {
        case call(samples: Int, text: String, ms: Double)
        case emit(String)
    }

    private struct Recorder: Transcribing {
        let inner: any Transcribing
        let log: OSAllocatedUnfairLock<[Event]>
        func transcribe(_ samples: [Float]) async throws -> String {
            let t0 = ContinuousClock.now
            let text = try await inner.transcribe(samples)
            let ms = Double(t0.duration(to: .now) / .microseconds(1)) / 1000
            log.withLock { $0.append(.call(samples: samples.count, text: text, ms: ms)) }
            return text
        }
    }

    /// `samples` are 16 kHz mono; trailing silence is appended here so the full speechEnd can fire.
    public static func run(samples original: [Float], config: AppConfig, transcriber: any Transcribing) async throws -> Report {
        var samples = original
        var trueEnd = 0
        var w = 0
        while w + 320 <= samples.count {
            var e: Float = 0
            for v in samples[w..<w + 320] { e += v * v }
            if (e / 320).squareRoot() > 0.005 { trueEnd = w + 320 }
            w += 320
        }
        let trueEndSec = Double(trueEnd) / 16000
        samples += [Float](repeating: 0, count: 24_000 + config.silenceMs * 16)

        let grammar = CommandGrammar(config: config.grammarConfig)
        let attention = config.attentionGate
        let log = OSAllocatedUnfairLock<[Event]>(initialState: [])
        let merge = MergeBuffer(
            merger: UtteranceMerger(windowMs: config.mergeWindowMs, unfinishedWindowMs: config.mergeWindowUnfinishedMs),
            gate: attention,
            isComplete: { VoicePipeline.isComplete($0, mode: $1, grammar: grammar, attention: attention) },
            carriesSpokenText: { VoicePipeline.carriesSpokenText($0, grammar: grammar, attention: attention) },
            onHold: { _ in },
            emit: { text, _ in log.withLock { $0.append(.emit(text)) } })
        let vad = try await VoiceActivity(silenceMs: config.silenceMs, earlySilenceMs: config.earlySilenceMs)

        let (jobs, jobCont) = AsyncStream<VoicePipeline.ASRJob>.makeStream(bufferingPolicy: .bufferingNewest(4))
        let recorder = Recorder(inner: transcriber, log: log)
        let asr = Task { await VoicePipeline.runASR(jobs, transcriber: recorder, merge: merge) }

        var assembler = UtteranceAssembler()
        var voiceEnd: ContinuousClock.Instant?
        var earlySnapshots: [(samples: Int, chunkEnd: Double)] = []
        var fullSegment: UtteranceSegment?
        var fullChunkEnd: Double?
        let start = ContinuousClock.now
        var i = 0
        while i + 4096 <= samples.count {
            let chunk = Array(samples[i..<i + 4096])
            let chunkEnd = Double(i + 4096) / 16000
            // The chunk "arrives" when its audio has been spoken, as from the microphone.
            let due = start + .milliseconds(Int(chunkEnd * 1000))
            if due > .now { try await Task.sleep(until: due, clock: .continuous) }
            let step = try await vad.analyze(chunk)
            let ev = step.event
            if ev == .speechStart { await merge.speechStarted() }
            if step.voiced { voiceEnd = .now }
            if let segment = assembler.pushSegment(chunk, event: ev, voiced: step.voiced) {
                fullSegment = segment
                fullChunkEnd = chunkEnd
                jobCont.yield(.init(kind: .full, segment: segment, at: .now, voiceEnd: voiceEnd))
            } else if ev == .speechEnd {
                await merge.speechAbandoned()
            } else if ev == .earlySilence, await merge.wantsEarlyPass, let segment = assembler.snapshot() {
                earlySnapshots.append((segment.samples.count, chunkEnd))
                jobCont.yield(.init(kind: .early, segment: segment, at: .now, voiceEnd: voiceEnd))
            }
            i += 4096
        }
        jobCont.finish()
        await asr.value
        await merge.reset()
        let events = log.withLock { $0 }

        // Each early pass is the call with its snapshot's sample count; it was accepted when the next event is an emit.
        var earlyText: String?
        var accepted = false
        var earlyReady: Double?
        for snap in earlySnapshots {
            guard let idx = events.firstIndex(where: { if case .call(let n, _, _) = $0 { return n == snap.samples }; return false }),
                  case .call(_, let text, let ms) = events[idx] else { continue }
            let took: Bool
            if idx + 1 < events.count, case .emit = events[idx + 1] { took = true } else { took = false }
            if earlyText == nil || (took && !accepted) { earlyText = text }
            if took && !accepted {
                accepted = true
                earlyReady = (snap.chunkEnd - trueEndSec) * 1000 + ms
            }
        }

        // The reference: what the full pass hears on the whole utterance, whether or not an early close used it.
        var fullText: String?
        var fullReady: Double?
        if let seg = fullSegment, let chunkEnd = fullChunkEnd {
            let t0 = ContinuousClock.now
            fullText = try await transcriber.transcribe(seg.samples)
            let ms = Double(t0.duration(to: .now) / .microseconds(1)) / 1000
            fullReady = (chunkEnd - trueEndSec) * 1000 + ms
        }

        func actions(_ text: String) -> [Action]? {
            var phrase = text
            if case .addressed(let rest) = attention.check(text) { phrase = rest }
            return grammar.parse(phrase)
        }
        var same: Bool?
        if let e = earlyText, let f = fullText {
            same = attention.isStop(e) || attention.isStop(f)
                ? attention.isStop(e) && attention.isStop(f)
                : actions(e) == actions(f)
        }
        let emitted = events.compactMap { event -> String? in if case .emit(let t) = event { return t }; return nil }
        return Report(trueEnd: trueEndSec, earlyFired: earlySnapshots.count, earlyText: earlyText, earlyAccepted: accepted,
                      fullText: fullText, sameAction: same, earlyReadyMs: earlyReady, fullReadyMs: fullReady, emitted: emitted)
    }
}
