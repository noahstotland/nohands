import FluidAudio
import Foundation
import NoHandsCore

/// Silero VAD (FluidAudio) wrapped so FluidAudio types do not leak out of NoHandsMac.
public actor VoiceActivity {
    private let manager: VadManager
    private let segmentation: VadSegmentationConfig
    private var state: VadStreamState
    private var early: EarlySilenceDetector
    private let speechThreshold: Float

    /// One chunk's verdict: the event, and whether the VAD called the chunk voiced (probability at or above the speech threshold).
    public struct Step: Sendable, Equatable {
        public var event: VadEvent
        public var voiced: Bool
    }

    /// silenceMs: trailing silence before speechEnd fires. earlySilenceMs: a shorter silence that raises
    /// `.earlySilence` once per run (0 = never; see `EarlySilenceDetector` for when it turns itself off).
    public init(silenceMs: Int = 1000, earlySilenceMs: Int = 0, speechThreshold: Float = 0.85,
                negativeThreshold: Float? = nil) async throws {
        let m = try await VadManager(config: VadConfig(defaultThreshold: speechThreshold))
        manager = m
        var cfg = VadSegmentationConfig.default
        // FluidAudio starts its silence timer at the END of the first silent 4096-sample chunk (256 ms hop),
        // so a literal minSilenceDuration of silenceMs would need 1 + ceil(silenceMs/256) silent chunks
        // (768 ms for 350 ms; measured speechEnd lag ~0.8-1.0 s). Instead require round(silenceMs/256) silent
        // chunks in total: 350 ms -> 1 chunk (measured lag 300-500 ms), 600 ms -> 2 chunks.
        let chunks = max(1, Int((Double(silenceMs) / 256).rounded()))
        cfg.minSilenceDuration = Double((chunks - 1) * VadManager.chunkSize) / Double(VadManager.sampleRate)
        cfg.negativeThreshold = negativeThreshold
        segmentation = cfg
        self.speechThreshold = speechThreshold
        early = EarlySilenceDetector(earlySilenceMs: earlySilenceMs, silenceMs: silenceMs,
                                     speechThreshold: speechThreshold, negativeThreshold: negativeThreshold)
        state = await m.makeStreamState()
    }

    /// `chunk` must be VadManager.chunkSize (4096) samples at 16 kHz. The event is the VAD's own, else
    /// `.earlySilence` from the detector: a real speechStart or speechEnd always wins.
    public func analyze(_ chunk: [Float]) async throws -> Step {
        let r = try await manager.processStreamingChunk(
            chunk, state: state, config: segmentation, returnSeconds: false, timeResolution: 2)
        state = r.state
        let voiced = r.probability >= speechThreshold
        let own: VadEvent
        switch r.event?.kind {
        case .speechStart: own = .speechStart
        case .speechEnd: own = .speechEnd
        case nil: own = .none
        }
        let wantsEarly = early.feed(probability: r.probability)
        if own != .none {
            early.reset()
            return Step(event: own, voiced: voiced)
        }
        return Step(event: wantsEarly ? .earlySilence : .none, voiced: voiced)
    }

    /// `analyze` for callers that only want the event.
    public func process(_ chunk: [Float]) async throws -> VadEvent { try await analyze(chunk).event }

    public func reset() async {
        state = await manager.makeStreamState()
        early.reset()
    }
}
