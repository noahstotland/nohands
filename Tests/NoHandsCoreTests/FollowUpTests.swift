import Testing
import Foundation
@testable import NoHandsCore

@Test func followUpPhrasesRefer() {
    let table: [(String, Bool)] = [
        ("no, the second one", true), ("No!", true), ("nope not that", true), ("not that one", true), ("the other one", true),
        ("the next one", true), ("next one please", true), ("instead open mail", true), ("also mute it", true),
        ("and then scroll down", true), ("Go back to the results", true), ("actually the first one", true), ("wrong one", true),
        ("notes", false), ("nothing", false), ("now open mail", false), ("another tab", false), ("open the other window", false),
        ("go back", false), ("", false),
    ]
    for (goal, expected) in table { #expect(FollowUp.refers(goal) == expected, "\(goal)") }
}

@Test func followUpMemoryNeedsAKeptTaskAnOpenWindowAndAReferringGoal() {
    let kept = EarlierTask(goal: "play lofi", history: [], result: "done: playing")
    let end = ContinuousClock.now
    func memory(_ task: EarlierTask?, after ms: Int, window: Int = 30000, goal: String = "no, the other one") -> Bool {
        FollowUp.memory(task, endedAt: end, now: end + .milliseconds(ms), windowMs: window, goal: goal) != nil
    }
    #expect(memory(kept, after: 0)); #expect(memory(kept, after: 29999))
    #expect(!memory(kept, after: 30000)); #expect(!memory(kept, after: 60000))
    #expect(!memory(kept, after: 1, window: 0)); #expect(!memory(nil, after: 1))
    #expect(!memory(kept, after: 1, goal: "open mail"))
}
