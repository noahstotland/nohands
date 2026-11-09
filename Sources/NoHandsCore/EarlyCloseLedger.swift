import Foundation

/// Which audio the serial ASR loop transcribes for early and full jobs. Remembers, per segment, how much audio an
/// accepted early close already used; what follows is the next utterance, and is skipped unless the VAD heard voice in it.
public struct EarlyCloseLedger: Sendable {
    private let maxEarlySamples: Int
    private var used: [Int: Int] = [:]      // segment id -> samples already acted on

    /// maxEarlySeconds: no grammar command is longer, and long speech must not pay for repeated early passes.
    public init(sampleRate: Int = 16_000, maxEarlySeconds: Int = 4) {
        maxEarlySamples = sampleRate * maxEarlySeconds
    }

    /// Record that the early text for `segment` was acted on.
    public mutating func recordEarlyClose(_ segment: UtteranceSegment) {
        used[segment.id] = segment.samples.count
    }

    /// The audio to try for an early pass, or nil to skip it.
    public func audio(forEarly segment: UtteranceSegment) -> [Float]? {
        let offset = used[segment.id] ?? 0
        guard segment.voicedEnd > offset, let rest = remainder(of: segment), rest.count <= maxEarlySamples else { return nil }
        return rest
    }

    /// The audio for the full pass, or nil when an early close used everything voiced. Closes the segment.
    public mutating func audio(forFull segment: UtteranceSegment) -> [Float]? {
        defer { used = used.filter { $0.key > segment.id } }
        return remainder(of: segment)
    }

    private func remainder(of segment: UtteranceSegment) -> [Float]? {
        guard let offset = used[segment.id] else { return segment.samples }
        guard segment.voicedEnd > offset else { return nil }
        return Array(segment.samples[offset...])
    }
}
