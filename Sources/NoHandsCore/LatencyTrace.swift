import Foundation

public struct LatencyTrace: Sendable {
    public var speechEnd: ContinuousClock.Instant?
    public var asrDone: ContinuousClock.Instant?
    public var actionsDone: ContinuousClock.Instant?
    /// When the last voiced chunk arrived (chunk granularity, so it can understate by up to 256 ms).
    public var voiceEnd: ContinuousClock.Instant?
    public init() {}

    /// When the user's voice stopped: the last voiced chunk, else the VAD's speechEnd (which lags the voice by the
    /// silence wait).
    public var utteranceEnd: ContinuousClock.Instant? { voiceEnd ?? speechEnd }

    /// e.g. "asr=187ms total=412ms sinceVoice=700ms"; total and sinceVoice run to actionsDone, or asrDone if actions
    /// have not finished. sinceVoice starts at `voiceEnd`, so it includes the silence wait that total leaves out.
    public var summary: String {
        guard let start = speechEnd else { return "" }
        var parts: [String] = []
        if let a = asrDone { parts.append("asr=\(Self.ms(start.duration(to: a)))ms") }
        if let end = actionsDone ?? asrDone { parts.append("total=\(Self.ms(start.duration(to: end)))ms") }
        if let v = voiceEnd, let end = actionsDone ?? asrDone { parts.append("sinceVoice=\(Self.ms(v.duration(to: end)))ms") }
        return parts.joined(separator: " ")
    }

    private static func ms(_ d: Duration) -> Int {
        let c = d.components
        return Int((Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15).rounded())
    }
}
