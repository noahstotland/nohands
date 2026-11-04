import Foundation

public struct LatencyTrace: Sendable {
    public var speechEnd: ContinuousClock.Instant?
    public var asrDone: ContinuousClock.Instant?
    public var actionsDone: ContinuousClock.Instant?
    public init() {}

    /// e.g. "asr=187ms total=412ms"; total runs to actionsDone, or asrDone if actions have not finished.
    public var summary: String {
        guard let start = speechEnd else { return "" }
        var parts: [String] = []
        if let a = asrDone { parts.append("asr=\(Self.ms(start.duration(to: a)))ms") }
        if let end = actionsDone ?? asrDone { parts.append("total=\(Self.ms(start.duration(to: end)))ms") }
        return parts.joined(separator: " ")
    }

    private static func ms(_ d: Duration) -> Int {
        let c = d.components
        return Int((Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15).rounded())
    }
}
