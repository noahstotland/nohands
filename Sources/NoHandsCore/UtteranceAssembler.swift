import Foundation

public enum VadEvent: Equatable, Sendable { case speechStart, speechEnd, none }

/// Collects VAD-segmented audio into utterances (speech plus a short pre-pad of preceding silence).
public struct UtteranceAssembler: Sendable {
    private let sampleRate: Int
    private let prePadSamples: Int
    private let minSpeechSamples: Int
    private let maxSpeechSamples: Int
    private var preRoll: [Float] = []
    private var speech: [Float] = []
    private var padCount = 0
    private var inSpeech = false

    /// prePadMs: audio kept before speechStart; minSpeechMs: shorter utterances are dropped; maxSpeechMs: forced cut.
    public init(sampleRate: Int = 16_000, prePadMs: Int = 200, minSpeechMs: Int = 250, maxSpeechMs: Int = 15_000) {
        self.sampleRate = sampleRate
        self.prePadSamples = max(0, prePadMs) * sampleRate / 1000
        self.minSpeechSamples = max(0, minSpeechMs) * sampleRate / 1000
        self.maxSpeechSamples = max(1, maxSpeechMs) * sampleRate / 1000
    }

    /// Feed one chunk and its VAD event; returns a completed utterance (speech + pre-pad) when one ends.
    public mutating func push(_ samples: [Float], event: VadEvent) -> [Float]? {
        if event == .speechStart && !inSpeech {
            inSpeech = true
            speech = preRoll
            padCount = preRoll.count
            preRoll.removeAll(keepingCapacity: true)
        }
        guard inSpeech else {
            preRoll.append(contentsOf: samples)
            if preRoll.count > prePadSamples { preRoll.removeFirst(preRoll.count - prePadSamples) }
            return nil
        }
        speech.append(contentsOf: samples)
        let speechCount = speech.count - padCount
        if event == .speechEnd || speechCount >= maxSpeechSamples {
            let out = speechCount >= minSpeechSamples ? speech : nil
            speech = []
            padCount = 0
            inSpeech = false
            return out
        }
        return nil
    }
}
