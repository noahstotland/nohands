import Testing
import Foundation
@testable import NoHandsCore

@Test func planGatePassesOnlyGoalsThatLookMultiStep() {
    let yes = ["put on the latest outdoor boys video", "open the first google result for sourdough starter",
               "open the top post on reddit right now", "open the readme of the swift repo on github",
               "show me the docs at docs.acme.dev please", "watch the new episode of some show"]
    let no = ["play it", "open reddit", "put on the latest outdoor boys video in safari",
              "watch the newest video in google chrome", "play this video again please",
              "click the current video thumbnail", "scroll down a little on this page",
              "write the notes down for the team today", "open the file notes.txt in the editor"]
    for g in yes { #expect(PlanGate.mayPlan(goal: g), "\(g)") }
    for g in no { #expect(!PlanGate.mayPlan(goal: g), "\(g)") }
}

@Test func planTextFoldsCaseAccentsSpacesAndPunctuation() {
    let hits = [("outdoorboys", "Outdoor Boys - YouTube"), ("Crème Brûlée", "creme-brulee recipe"), ("Q&A", "q a"), ("42", "Top 42")]
    let misses = [("outdoor boys", "Indoor Girls"), ("", "anything"), ("  ", "anything"), ("moon landing", "Moon")]
    for (n, h) in hits { #expect(PlanText.matches(n, in: h), "\(n) in \(h)") }
    for (n, h) in misses { #expect(!PlanText.matches(n, in: h), "\(n) in \(h)") }
}

private func check(_ kind: String, _ text: String) -> String {
    text.isEmpty ? #"{"kind":"\#(kind)"}"# : #"{"kind":"\#(kind)","text":"\#(text)"}"#
}
private func openStep(_ url: String = "https://videos.acme.dev/outdoor", expect: String? = nil) -> String {
    #"{"intent":"Open it","do":"open_url","url":"\#(url)","expect":\#(expect ?? check("url_contains", "acme"))}"#
}
private let clickStep = #"{"intent":"Open the first one","do":"click_first_item","after":"Videos","expect":{"kind":"title_contains","text":"outdoor boys"}}"#
private let mediaStep = #"{"intent":"Play it","do":"wait_for_media","expect":{"kind":"media_playing"}}"#
private func plan(_ steps: String...) -> String { #"{"plan":[\#(steps.joined(separator: ","))]}"# }

@Test func planDecodingKeepsOnlyWholeKnownPlans() {
    let ok = plan(openStep(), clickStep, mediaStep)
    #expect(TaskPlan.decode(fromPayloadText: ok)?.steps.map(\.kind) == [.openURL, .clickFirstItem, .waitForMedia])
    let none = [#"{"plan":null}"#, #"{"plan":[]}"#, "{}", "not json", "", "[]",
                plan(openStep(), #"{"intent":"x","do":"type_text","text":"hi","expect":{"kind":"element_present","text":"a"}}"#),
                plan(openStep(), #"{"intent":"x","do":"click","text":"Go","expect":{"kind":"page_is_pretty","text":"a"}}"#),
                plan(openStep(), #"{"intent":"x","do":"click","expect":{"kind":"element_present","text":"a"}}"#),
                plan(openStep(), #"{"intent":"x","do":"click","text":"Go","expect":{"kind":"element_present"}}"#),
                plan(openStep(), #"{"intent":"x","do":"open_url","expect":{"kind":"url_contains","text":"a"}}"#)]
    for p in none { #expect(TaskPlan.decode(fromPayloadText: p) == nil, "\(p)") }
}

@Test func planDecodingReadsBothResponseEnvelopes() {
    let text = plan(openStep(), mediaStep)
    let claude = try! JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": text]]])
    let refused = try! JSONSerialization.data(withJSONObject: ["stop_reason": "refusal", "content": [["type": "text", "text": text]]])
    let ollama = try! JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": text]])
    #expect(TaskPlan.decode(fromResponse: claude)?.steps.count == 2)
    #expect(TaskPlan.decode(fromResponse: refused) == nil)
    #expect(TaskPlan.decode(fromOllamaResponse: ollama)?.steps.count == 2)
    #expect(TaskPlan.decode(fromOllamaResponse: claude) == nil)
}

@Test func planValidationRejectsWhatItMustAndNormalizesTheRest() {
    let goal = "put on the latest outdoor boys video"
    func valid(_ p: String, goal g: String = goal) -> TaskPlan? { TaskPlan.decode(fromPayloadText: p)?.validated(goal: g) }
    let good = plan(openStep(), clickStep, mediaStep)
    #expect(valid(good) != nil)
    let long = String(repeating: "a", count: 81)
    let tooMany = plan(openStep(), clickStep, clickStep, clickStep, clickStep, clickStep, clickStep, clickStep, mediaStep)
    let rejected: [(String, String)] = [
        ("one step", plan(mediaStep)),
        ("nine steps", tooMany),
        ("file url", plan(openStep("file:///etc/passwd"), clickStep, mediaStep)),
        ("javascript url", plan(openStep("javascript:alert(1)"), clickStep, mediaStep)),
        ("example host", plan(openStep("https://videos.example/outdoor"), clickStep, mediaStep)),
        ("example subdomain", plan(openStep("https://a.b.example"), clickStep, mediaStep)),
        ("long check text", plan(openStep(expect: check("url_contains", long)), clickStep, mediaStep)),
        ("check on general words only", plan(openStep(expect: check("url_contains", "video")),
            #"{"intent":"c","do":"click_first_item","expect":{"kind":"element_present","text":"latest"}}"#, mediaStep)),
        ("playback goal not ending in wait_for_media", plan(openStep(), clickStep)),
    ]
    for (why, p) in rejected { #expect(valid(p) == nil, "\(why)") }
    // A goal that wants no playback needs no wait_for_media.
    #expect(valid(plan(openStep(), clickStep), goal: "open the outdoor boys channel page") != nil)
    // The goal's own word, matched with spaces and case folded, ties a check to the goal.
    #expect(valid(plan(openStep(expect: check("title_contains", "OutdoorBoys")), mediaStep)) != nil)
    // Bare domains are turned into absolute https URLs; intents lose control characters and length.
    let tidy = valid(plan(openStep("videos.acme.dev/x").replacingOccurrences(of: "Open it", with: "Open\\nit " + long), clickStep, mediaStep))
    #expect(tidy?.steps[0].url == "https://videos.acme.dev/x")
    #expect(tidy?.steps[0].intent.contains("\n") == false)
    #expect((tidy?.steps[0].intent.count ?? 99) <= 80)
}
