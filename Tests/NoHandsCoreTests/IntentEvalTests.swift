import Testing
import Foundation
@testable import NoHandsCore

@Test func evalMatchingNormalizes() {
    let want: [Action] = [.openApp("Google Chrome"), .pressKey(KeyChord(.l, [.command])), .typeText("youtube.com"), .pressKey(KeyChord(.return))]
    #expect(IntentEval.matches([.openApp("chrome"), .pressKey(KeyChord(.l, [.command])), .typeText("https://www.YouTube.com/"), .pressKey(KeyChord(.return))], anyOf: [want]))
    #expect(!IntentEval.matches([.openApp("Google Chrome")], anyOf: [want]))
    #expect(IntentEval.matches([.ignore], anyOf: [want, [.ignore]]))
}

@Test func evalFixtureDecodes() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../scripts/intent-eval.json")
    let cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: url))
    #expect(cases.count >= 25)
    #expect(cases.allSatisfy { !$0.accept.isEmpty && $0.accept.allSatisfy { !$0.actions.isEmpty || $0.status == .ask } })
}

@Test func evalMatchingWithStatus() {
    let ask = EvalAnswer(actions: [], status: .ask)
    let click = EvalAnswer(actions: [.click(.label(2), button: .left, count: 1)])
    let rows: [(got: [Action], status: StepStatus, want: [EvalAnswer], matches: Bool)] = [
        ([], .ask, [ask], true),
        ([.ignore], .ask, [ask], true),              // an ask entry ignores the actions
        ([.click(.label(2), button: .left, count: 1)], .continue, [ask], false),
        ([], .ask, [click], false),                  // an entry without a status still compares actions
        ([.click(.label(2), button: .left, count: 1)], .done, [ask, click], true),
    ]
    for r in rows {
        #expect(IntentEval.matches(r.got, status: r.status, anyOf: r.want) == r.matches, "\(r.got) \(r.status)")
    }
}

@Test func evalSummaryLines() {
    func line(_ r: [(Bool, Int)], drop: Int = 0) -> String {
        EvalSummary(results: r.map { (passed: $0.0, ms: $0.1) }, dropFirst: drop).line
    }
    #expect(line([]) == "pass=0/0 (0%) p50=0ms p95=0ms")
    #expect(line([(true, 100), (true, 300), (true, 200)]) == "pass=3/3 (100%) p50=200ms p95=300ms")
    // even count: nearest rank takes the lower middle; failures and errors still count their time
    #expect(line([(true, 10), (false, 40), (true, 20), (false, 30)]) == "pass=2/4 (50%) p50=20ms p95=40ms")
    // dropFirst changes latency only
    #expect(line([(true, 5000), (false, 100), (true, 200)], drop: 1) == "pass=2/3 (66%) p50=100ms p95=200ms")
    // dropping can never empty the sample
    #expect(line([(true, 70)], drop: 2) == "pass=1/1 (100%) p50=70ms p95=70ms")
    #expect(line([(true, 70)], drop: -3) == "pass=1/1 (100%) p50=70ms p95=70ms")
}
