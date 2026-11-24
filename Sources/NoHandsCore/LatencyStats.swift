import Foundation

/// Percentiles and the summary line `nohands-cli bench` prints for each stage. Pure: no audio, no I/O.
public enum LatencyStats {
    /// Nearest rank: the smallest value with at least `p` percent of the values at or below it. nil when empty.
    public static func percentile(_ values: [Double], _ p: Int) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((Double(min(max(p, 0), 100)) / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    /// `"<stage padded to 10> p50=<v> p95=<v>"`. Values under 10 ms keep two decimals, others print whole
    /// milliseconds. Empty `values` print `p50=n/a p95=n/a`.
    public static func summaryLine(stage: String, values: [Double]) -> String {
        let name = stage.padding(toLength: max(stage.count, 10), withPad: " ", startingAt: 0)
        return "\(name) p50=\(format(percentile(values, 50))) p95=\(format(percentile(values, 95)))"
    }

    /// One value as the summary and the per-file rows print it: two decimals under 10 ms, else whole milliseconds.
    public static func format(_ ms: Double?) -> String {
        guard let ms else { return "n/a" }
        return abs(ms) < 10 ? String(format: "%.2fms", ms) : String(format: "%.0fms", ms)
    }
}
