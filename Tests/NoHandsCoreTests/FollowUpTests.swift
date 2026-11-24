import Testing
import Foundation
@testable import NoHandsCore

@Test func followUpPhrasesRefer() {
    let table: [(String, Bool)] = [
        ("no, the second one", true), ("No!", false), ("no thanks", true), ("actually", false), ("also", false), ("nope", false), ("nope not that", true), ("not that one", true), ("the other one", true),
        ("the next one", true), ("next one please", true), ("instead open mail", true), ("also mute it", true),
        ("and then scroll down", true), ("Go back to the results", true), ("actually the first one", true), ("wrong one", true), ("the other", true), ("wrong one please", true),
        ("notes", false), ("nothing", false), ("now open mail", false), ("another tab", false), ("open the other window", false),
        ("go back", false), ("", false),
    ]
    for (goal, expected) in table { #expect(FollowUp.refers(goal) == expected, "\(goal)") }
}

@Test func followUpGoalsKeepTheNewWordsAndSkipPlaybackForPause() {
    // (new words, expected goal for the playback check): the earlier goal joins unless they ask to pause, stop or mute.
    let table: [(String, String)] = [("no, the other one", "play lofi no, the other one"), ("no, pause it", "no, pause it"), ("no, mute", "no, mute")]
    for (goal, want) in table { #expect(FollowUp.playbackGoal(earlier: "play lofi", goal: goal) == want, "\(goal)") }
    #expect(FollowUp.playbackGoal(earlier: nil, goal: "pause") == "pause")
    // Over the limit the older part is cut and the new words stay whole.
    #expect(FollowUp.chained(earlier: "play lofi", goal: "no, the other", limit: 100) == "play lofi; then: no, the other")
    #expect(FollowUp.chained(earlier: "play lofi on youtube", goal: "no, the other", limit: 30) == "play lofi; then: no, the other")
    #expect(FollowUp.chained(earlier: "x", goal: String(repeating: "a", count: 50), limit: 30) == String(repeating: "a", count: 30))
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
