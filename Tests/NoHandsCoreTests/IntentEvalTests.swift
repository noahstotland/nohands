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
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Scripts/intent-eval.json")
    let cases = try JSONDecoder().decode([EvalCase].self, from: Data(contentsOf: url))
    #expect(cases.count >= 25)
    #expect(cases.allSatisfy { !$0.accept.isEmpty && $0.accept.allSatisfy { !$0.isEmpty } })
}
