import FluidAudio
import Foundation

public protocol Transcribing: Sendable { func transcribe(_ samples: [Float]) async throws -> String }

/// Parakeet TDT batch ASR (FluidAudio). Downloads models to FluidAudio's cache on first use.
public actor ParakeetTranscriber: Transcribing {
    private let manager: AsrManager

    /// version: "v2" | "v3"
    public init(version: String) async throws {
        let models = try await AsrModels.downloadAndLoad(version: version == "v3" ? .v3 : .v2)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        var decoderState = TdtDecoderState.make()   // fresh state per utterance
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads any audio file and returns 16 kHz mono Float32 samples.
public func loadSamples16k(path: String) throws -> [Float] {
    try AudioConverter().resampleAudioFile(path: path)
}
