import FluidAudio
import Foundation
import NoHandsCore

/// Silero VAD (FluidAudio) wrapped so FluidAudio types do not leak out of NoHandsMac.
public actor VoiceActivity {
    private let manager: VadManager
    private let segmentation: VadSegmentationConfig
    private var state: VadStreamState

    /// silenceMs: trailing silence before speechEnd fires.
    public init(silenceMs: Int = 350) async throws {
        let m = try await VadManager()
        manager = m
        var cfg = VadSegmentationConfig.default
        cfg.minSilenceDuration = Double(silenceMs) / 1000
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
