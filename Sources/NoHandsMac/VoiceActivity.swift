import FluidAudio
import Foundation
import NoHandsCore

/// Silero VAD (FluidAudio) wrapped so FluidAudio types do not leak out of NoHandsMac.
public actor VoiceActivity {
    private let manager: VadManager
    private let segmentation: VadSegmentationConfig
    private var state: VadStreamState

    /// silenceMs: trailing silence before speechEnd fires.
    public init(silenceMs: Int = 1000, speechThreshold: Float = 0.85, negativeThreshold: Float? = nil) async throws {
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
        state = await m.makeStreamState()
    }

    /// `chunk` must be VadManager.chunkSize (4096) samples at 16 kHz.
    public func process(_ chunk: [Float]) async throws -> VadEvent {
        let r = try await manager.processStreamingChunk(
            chunk, state: state, config: segmentation, returnSeconds: false, timeResolution: 2)
        state = r.state
        switch r.event?.kind {
        case .speechStart: return .speechStart
        case .speechEnd: return .speechEnd
        case nil: return .none
        }
    }

    public func reset() async {
        state = await manager.makeStreamState()
    }
}
