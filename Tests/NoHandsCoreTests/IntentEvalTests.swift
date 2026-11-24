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
