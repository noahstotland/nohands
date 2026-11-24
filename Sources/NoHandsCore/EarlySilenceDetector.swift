import Foundation

/// Raises one signal per silent run when a short silence (`earlySilenceMs`) follows speech, well before the VAD's
/// own `silenceMs` ends the utterance. Reads the Silero probability the VAD already returns, with FluidAudio's
/// hysteresis: at or above `speechThreshold` is speech and clears the run; below the negative threshold, while in
/// speech, starts a run; in between neither starts nor clears one (a started run keeps counting through it).
public struct EarlySilenceDetector: Sendable {
    /// One VAD chunk is 4096 samples at 16 kHz.
    public static let chunkMs = 256.0

    private let speechThreshold: Float
    private let negativeThreshold: Float
    private let fireAt: Int          // chunks; 0 = off
    private var inSpeech = false
    private var run = 0              // chunks in the current silent run; 0 = no run
    private var fired = false

    /// Off (never fires) when `earlySilenceMs` is 0 or its chunk count is not below `silenceMs`'s.
    public init(earlySilenceMs: Int, silenceMs: Int, speechThreshold: Float = 0.85, negativeThreshold: Float? = nil) {
        func chunks(_ ms: Int) -> Int { max(1, Int((Double(ms) / Self.chunkMs).rounded())) }
        let early = chunks(earlySilenceMs)
        fireAt = earlySilenceMs > 0 && early < chunks(silenceMs) ? early : 0
        self.speechThreshold = speechThreshold
        self.negativeThreshold = negativeThreshold ?? speechThreshold - 0.15
    }

    public var isEnabled: Bool { fireAt > 0 }

    /// Feed one chunk's speech probability; true on the chunk where the run reaches the early length (once per run).
    public mutating func feed(probability: Float) -> Bool {
        guard fireAt > 0 else { return false }
        if probability >= speechThreshold {
            inSpeech = true; run = 0; fired = false
            return false
        }
        if run > 0 { run += 1 } else if inSpeech && probability < negativeThreshold { run = 1 }
        guard run >= fireAt, !fired else { return false }
        fired = true
        return true
    }

    /// Call on the VAD's own speechStart/speechEnd and when the pipeline resets.
    public mutating func reset() { inSpeech = false; run = 0; fired = false }
}
