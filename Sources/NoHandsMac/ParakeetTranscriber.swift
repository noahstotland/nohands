import CoreML
import FluidAudio
import Foundation

public protocol Transcribing: Sendable { func transcribe(_ samples: [Float]) async throws -> String }

/// Parakeet TDT batch ASR (FluidAudio). Downloads models to FluidAudio's cache on first use.
public actor ParakeetTranscriber: Transcribing {
    private let manager: AsrManager
    private let decoderLayers: Int
    /// Per-stage timing of the most recent call, when FluidAudio reports it (diagnostics).
    public private(set) var lastBreakdown = ""

    /// version: "v2" | "v3" | "ultra" | "110m" (tdtCtc110m); units (encoder, default "gpu": measured ~115 ms vs ~800 ms on the ANE/default placement on M1 Pro; nil = FluidAudio default): "ane" | "gpu" | "all" | "cpu";
    /// precision: nil | "int8" | "int8-v2".
    public init(version: String, encoderUnits: String? = "gpu", precision: String? = nil) async throws {
        let v: AsrModelVersion
        switch version {
        case "v3": v = .v3
        case "ultra": v = .ultra
        case "110m": v = .tdtCtc110m
        default: v = .v2
        }
        let units: MLComputeUnits?
        switch encoderUnits {
        case "ane": units = .cpuAndNeuralEngine
        case "gpu": units = .cpuAndGPU
        case "all": units = .all
        case "cpu": units = .cpuOnly
        default: units = nil
        }
        let models = try await AsrModels.downloadAndLoad(
            version: v,
            encoderPrecision: ParakeetEncoderPrecision(rawValue: precision ?? "int8") ?? .int8,
            encoderComputeUnits: units)
        let m = AsrManager(config: .default)
        try await m.loadModels(models)
        manager = m
        decoderLayers = v.decoderLayers
    }

    public func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { return "" }
        // FluidAudio rejects audio shorter than ASRConstants.minimumAudioDurationSeconds (0.3 s); pad with silence.
        var samples = samples
        let minimum = ASRConstants.minimumRequiredSamples(forSampleRate: ASRConstants.sampleRate)
        if samples.count < minimum { samples += [Float](repeating: 0, count: minimum - samples.count) }
        var decoderState = TdtDecoderState.make(decoderLayers: decoderLayers)   // fresh state per utterance
        let result = try await manager.transcribe(samples, decoderState: &decoderState)
        if let m = result.performanceMetrics {
            lastBreakdown = String(format: "pre=%.0fms enc=%.0fms dec=%.0fms", m.preprocessorTime * 1000, m.encoderTime * 1000, m.decoderTime * 1000)
        }
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Reads any audio file and returns 16 kHz mono Float32 samples.
public func loadSamples16k(path: String) throws -> [Float] {
    try AudioConverter().resampleAudioFile(path: path)
}
