import Foundation

/// `earlySilence` is not from the VAD: `EarlySilenceDetector` raises it when a short silence follows speech.
public enum VadEvent: Equatable, Sendable { case speechStart, speechEnd, earlySilence, none }

/// Audio of one utterance segment. `id` changes at every close (even a dropped or forced one); `voicedEnd` is the
/// sample index after the last chunk the VAD called voiced.
public struct UtteranceSegment: Equatable, Sendable {
    public var id: Int
    public var samples: [Float]
    public var voicedEnd: Int
    public init(id: Int, samples: [Float], voicedEnd: Int) {
        self.id = id; self.samples = samples; self.voicedEnd = voicedEnd
    }
}

/// Collects VAD-segmented audio into utterances (speech plus a short pre-pad of preceding silence).
public struct UtteranceAssembler: Sendable {
    private let sampleRate: Int
    private let prePadSamples: Int
    private let minSpeechSamples: Int
    private let maxSpeechSamples: Int
    private var preRoll: [Float] = []
    private var speech: [Float] = []
    private var padCount = 0
    private var loudEnd = 0          // end index (in `speech`) of the last chunk with audible energy
    private var inSpeech = false
    private var segmentID = 0
    private var voicedEnd = 0         // end index (in `speech`) of the last chunk the VAD called voiced
    /// Chunks quieter than this RMS count as silence for the min-speech check.
    private static let silenceRMS: Float = 0.01

    /// prePadMs: audio kept before speechStart (default two 256 ms chunks: the VAD reports speechStart after
    /// its own min-speech lag, so onset can sit a chunk earlier); minSpeechMs: shorter utterances are dropped
    /// (trailing silence chunks are excluded by an RMS check, so this is an approximation at chunk granularity);
    /// maxSpeechMs: forced cut (keep below Parakeet's ~15 s window, including pad).
    public init(sampleRate: Int = 16_000, prePadMs: Int = 512, minSpeechMs: Int = 250, maxSpeechMs: Int = 14_000) {
        self.sampleRate = sampleRate
        self.prePadSamples = max(0, prePadMs) * sampleRate / 1000
        self.minSpeechSamples = max(0, minSpeechMs) * sampleRate / 1000
        self.maxSpeechSamples = max(1, maxSpeechMs) * sampleRate / 1000
    }

    /// Discards any partial utterance and pre-roll (e.g. after an error).
    public mutating func reset() {
        preRoll = []; speech = []; padCount = 0; loudEnd = 0; voicedEnd = 0; inSpeech = false; segmentID += 1
    }

    /// The open segment so far, or nil outside speech. For the early pass on a short silence.
    public func snapshot() -> UtteranceSegment? {
        inSpeech ? UtteranceSegment(id: segmentID, samples: speech, voicedEnd: voicedEnd) : nil
    }

    /// Feed one chunk and its VAD event; returns a completed utterance (speech + pre-pad) when one ends.
    /// After a forced max-length cut the assembler stays in speech and starts a new segment (no pre-pad),
    /// so continuous speech yields consecutive utterances and the VAD's later speechEnd closes the last one.
    public mutating func push(_ samples: [Float], event: VadEvent) -> [Float]? {
        pushSegment(samples, event: event)?.samples
    }

    /// `push` that also returns the segment id and voiced end. `voiced` is the VAD's verdict on this chunk.
    /// `.earlySilence` adds nothing and returns nil; ask for `snapshot()`.
    public mutating func pushSegment(_ samples: [Float], event: VadEvent, voiced: Bool = true) -> UtteranceSegment? {
        if event == .speechStart && !inSpeech {
            inSpeech = true
            speech = preRoll
            padCount = preRoll.count
            loudEnd = padCount
            voicedEnd = 0
            preRoll.removeAll(keepingCapacity: true)
        }
        guard inSpeech else {
            preRoll.append(contentsOf: samples)
            if preRoll.count > prePadSamples { preRoll.removeFirst(preRoll.count - prePadSamples) }
            return nil
        }
        speech.append(contentsOf: samples)
        if Self.rms(samples) >= Self.silenceRMS { loudEnd = speech.count }
        if voiced { voicedEnd = speech.count }
        let forced = speech.count - padCount >= maxSpeechSamples
        if event == .speechEnd || forced {
            let out = loudEnd - padCount >= minSpeechSamples
                ? UtteranceSegment(id: segmentID, samples: speech, voicedEnd: voicedEnd) : nil
            speech = []; padCount = 0; loudEnd = 0; voicedEnd = 0; segmentID += 1
            inSpeech = forced && event != .speechEnd
            return out
        }
        return nil
    }

    private static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var s: Float = 0
        for v in x { s += v * v }
        return (s / Float(x.count)).squareRoot()
    }
}
