import Testing
@testable import NoHandsCore

@Test func latencyPercentilesAndSummaryLines() {
    // (stage, values, p50, p95, expected line)
    let table: [(String, [Double], Double?, Double?, String)] = [
        ("lag", [], nil, nil, "lag        p50=n/a p95=n/a"),
        ("asr", [141], 141, 141, "asr        p50=141ms p95=141ms"),
        // Unsorted input; nearest rank on 4 values: p50 is the 2nd smallest, p95 the largest.
        ("end-to-end", [1390, 453, 900, 600], 600, 1390, "end-to-end p50=600ms p95=1390ms"),
        // Sub-10 ms values keep two decimals; 20 values put p95 on the 19th.
        ("parse", (1...20).map { Double($0) / 100 }, 0.10, 0.19, "parse      p50=0.10ms p95=0.19ms"),
        // Whole-ms rounding at 10 ms and above.
        ("lag", [311.6, 311.6], 311.6, 311.6, "lag        p50=312ms p95=312ms"),
    ]
    for (stage, values, p50, p95, line) in table {
        #expect(LatencyStats.percentile(values, 50) == p50, "p50 of \(values)")
        #expect(LatencyStats.percentile(values, 95) == p95, "p95 of \(values)")
        #expect(LatencyStats.summaryLine(stage: stage, values: values) == line)
    }
}
