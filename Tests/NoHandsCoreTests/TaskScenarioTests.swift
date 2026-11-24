import Testing
import Foundation
@testable import NoHandsCore

private func scenario(name: String = "a", goal: String = #""g""#, start: String = #"{"app":"TextEdit"}"#, ready: String = "[]",
                      success: String = #"[{"windowTitleContains":"x"}]"#, steps: Int = 5) -> String {
    #"{"name":"\#(name)","goal":\#(goal),"start":\#(start),"ready":\#(ready),"success":\#(success),"maxSteps":\#(steps)}"#
}

private func obs(app: String = "Safari", title: String = "", url: String? = nil, elements: [String] = [],
                 media: MediaState? = nil) -> ScreenObservation {
    var o = ScreenObservation(app: app, windowTitle: title, url: url, mode: .command,
                              elements: elements.enumerated().map { ObservedElement(number: $0.offset + 1, role: "button", title: $0.element) })
    o.media = media
    return o
}

@Test func scenarioFileRejections() {
    let table: [(file: String, why: String)] = [
        ("not json", "JSON"),
        (#"[{"name":"nog","start":{"app":"X"},"success":[{"mediaPlaying":true}],"maxSteps":3}]"#, "nog: missing goal"),
        ("[\(scenario()),\(scenario())]", "duplicate"),
        ("[\(scenario(success: "[{}]"))]", "one key"),
        ("[\(scenario(success: #"[{"elementVisible":"x","mediaPlaying":true}]"#))]", "one key"),
        ("[\(scenario(success: #"[{"cursorNear":"x"}]"#))]", "unknown check"),
        ("[\(scenario(success: #"[{"urlMatches":"("}]"#))]", "regular expression"),
        ("[\(scenario(success: #"[{"elementVisible":""}]"#))]", "empty"),
        ("[\(scenario(success: #"[{"mediaPlaying":false}]"#))]", "mediaPlaying"),
        ("[\(scenario(success: "[]"))]", "success"),
        ("[\(scenario(start: #"{"app":"X","url":"https://a.com"}"#))]", "exactly one"),
        ("[\(scenario(start: "{}"))]", "exactly one"),
        ("[\(scenario(start: #"{"app":""}"#))]", "app is empty"),
        ("[\(scenario(start: #"{"url":"file:///etc/hosts"}"#))]", "http"),
        ("[\(scenario(steps: 0))]", "maxSteps"),
        ("[\(scenario(steps: 31))]", "maxSteps"),
        ("[\(scenario(success: #"[{"elementAbsent":"Accept"}]"#))]", "elementVisible"),
        ("[\(scenario(ready: #"[{"elementAbsent":"Accept"}]"#))]", "elementVisible"),
    ]
    for t in table {
        do {
            _ = try ScenarioFile.load(Data(t.file.utf8), run: 1)
            Issue.record("accepted: \(t.file)")
        } catch { #expect("\(error.localizedDescription)".contains(t.why), "\(t.why) in \(error.localizedDescription)") }
    }
}

@Test func scenarioFileDecodesAndSubstitutesRun() throws {
    let success = #"[{"windowTitleContains":"n-{run}"},{"urlMatches":"a\\.com"},{"elementVisible":"B"},{"elementAbsent":"C"},{"mediaPlaying":true}]"#
    let got = try ScenarioFile.load(Data("[\(scenario(goal: #""save as n-{run}""#, success: success))]".utf8), run: 42)
    #expect(got == [TaskScenario(name: "a", goal: "save as n-42", start: .app("TextEdit"), ready: [],
                                 success: [.windowTitleContains("n-42"), .urlMatches(#"a\.com"#), .elementVisible("B"),
                                           .elementAbsent("C"), .mediaPlaying], maxSteps: 5)])
}

@Test func checksHoldOnObservation() {
    let table: [(ScenarioCheck, ScreenObservation, Bool)] = [
        (.windowTitleContains("outdoor"), obs(title: "Outdoor Boys - YouTube"), true),
        (.windowTitleContains("engine"), obs(title: "Outdoor Boys"), false),
        (.urlMatches(#"youtube\.com/watch"#), obs(), false),
        (.urlMatches(#"youtube\.com/watch"#), obs(url: "https://WWW.YouTube.com/watch?v=x"), true),
        (.urlMatches(#"youtube\.com/watch"#), obs(url: "https://youtube.com/"), false),
        (.elementVisible("accept all"), obs(elements: ["Menu", "Accept All"]), true),
        (.elementVisible("accept all"), obs(elements: ["Menu"]), false),
        (.elementAbsent("accept"), obs(), false),
        (.elementAbsent("accept"), obs(elements: ["Accept"]), false),
        (.elementAbsent("accept"), obs(elements: ["Home"]), true),
        (.mediaPlaying, obs(media: .playing), true),
        (.mediaPlaying, obs(media: .paused), false),
        (.mediaPlaying, obs(media: MediaState.none), false),
        (.mediaPlaying, obs(), false),
    ]
    for (check, o, want) in table { #expect(check.holds(in: o) == want, Comment(rawValue: check.label)) }
}

@Test func startStateComparesHostAndPath() {
    let yt = ScenarioStart.url(URL(string: "https://www.youtube.com/")!)
    let table: [(ScenarioStart, ScreenObservation, Bool)] = [
        (yt, obs(url: "https://youtube.com"), true), (yt, obs(url: "https://www.youtube.com/"), true),
        (yt, obs(url: "https://www.youtube.com/watch?v=x"), false), (yt, obs(url: "https://example.com/"), false),
        (yt, obs(), false),
        (.app("textedit"), obs(app: "TextEdit", title: "Untitled"), true),
        (.app("TextEdit"), obs(app: "TextEdit", title: ""), false),
        (.app("TextEdit"), obs(app: "Safari", title: "Untitled"), false),
    ]
    for (start, o, want) in table { #expect(TaskScenario.startHolds(start, in: o) == want, "\(start) \(o.app) \(o.url ?? "-")") }
}

@Test func verdictTable() {
    let table: [(TaskEnd, Bool, ScenarioVerdict)] = [
        (.done, true, .pass), (.done, false, .falseDone),
        (.stuck, true, .unclaimed), (.failed, true, .unclaimed), (.ignored, true, .unclaimed),
        (.stuck, false, .fail), (.failed, false, .fail), (.ignored, false, .fail),
        (.stopped, true, .stopped), (.stopped, false, .stopped),
    ]
    for (end, holds, want) in table { #expect(TaskScenario.verdict(end: end, checksHold: holds) == want, "\(end) \(holds)") }
}

@Test func reportEscapesCells() {
    let results = [ScenarioResult(name: "a|b\nc\u{7}d\\|e", verdict: .falseDone, steps: 3, seconds: 12.34),
                   ScenarioResult(name: "ok", verdict: .pass, steps: 2, seconds: 5),
                   ScenarioResult(name: "z", verdict: .notRun, steps: 0, seconds: 0)]
    let rows = ScenarioReport.table(results).split(separator: "\n", omittingEmptySubsequences: false)
    #expect(rows.count == 5)   // header, rule, three results
    #expect(rows[2] == #"| a\|b c d\\\|e | false-done | 3 | 12.3 s |"#)
    #expect(!ScenarioReport.table(results).unicodeScalars.contains { $0.value < 0x20 && $0 != "\n" })
    #expect(ScenarioReport.summary(results) == "1 of 3 pass; false-done 1, not-run 1")
}

@Test func shippedScenarioFileLoads() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let loaded = try ScenarioFile.load(Data(contentsOf: root.appendingPathComponent("scripts/task-scenarios.json")), run: 1)
    #expect(!loaded.isEmpty)
}
