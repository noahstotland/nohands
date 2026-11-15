import Testing
import Foundation
@testable import NoHandsCore

@Test func joinKeepsOrderDropsEmptiesAndRepeats() {
    let table: [([String], String)] = [
        (["Raptors vs Celtics", "7:30 PM", "Watch"], "Raptors vs Celtics | 7:30 PM | Watch"),
        ([" Raptors \n vs  Celtics ", "", "  ", "Raptors vs Celtics", "7:30 PM"], "Raptors vs Celtics | 7:30 PM"), // trimmed, collapsed, repeat dropped
        (["Watch", "Raptors", "Watch"], "Watch | Raptors | Watch"),                                            // only an adjacent repeat goes
        ([], ""),
    ]
    for (runs, expected) in table { #expect(PageText.join(runs) == expected, "\(runs)") }
}

@Test func joinCutsAtTheLimitOnARunBoundary() {
    let run = String(repeating: "a", count: 1000)
    let five = (1...5).map { String($0) + run }          // 1001 characters each
    let cut = PageText.join(five)
    #expect(cut == (1...3).map { String($0) + run }.joined(separator: " | ") + " …")
    #expect(cut.count <= PageText.limit)
    // One run longer than the limit is cut inside the run.
    let long = PageText.join([String(repeating: "b", count: 9000)])
    #expect(long.count == PageText.limit && long.hasSuffix(" …"))
    // Exactly at the limit is not cut.
    #expect(PageText.join([String(repeating: "c", count: PageText.limit)]).count == PageText.limit)
    #expect(!PageText.join([String(repeating: "c", count: PageText.limit)]).hasSuffix("…"))
}

@Test func genericTitlesAreRecognised() {
    let table: [(String, Bool)] = [
        ("Watch", true), ("watch now", true), ("  WATCH LIVE! ", true), ("Read more…", true), ("Learn   more.", true),
        ("Click here", true), ("", true), ("  ", true), ("More", true), ("Details", true),
        ("Watch the Raptors", false), ("Raptors", false), ("Play next episode", false), ("Open settings", false),
    ]
    for (title, generic) in table { #expect(PageText.isGeneric(title) == generic, "\(title)") }
}

@Test func nearKeepsTheLastWordsBeforeTheLink() {
    let table: [(String, String?)] = [
        ("Raptors vs Celtics 7:30 PM", "Raptors vs Celtics 7:30 PM"),
        ("  Raptors \n vs  Celtics ", "Raptors vs Celtics"),
        ("Tonight on TSN: Toronto Raptors vs Boston Celtics 7:30 PM", "Raptors vs Boston Celtics 7:30 PM"),  // cut on a word
        (String(repeating: "x", count: 60), String(repeating: "x", count: 40)),                                          // no space: hard cut
        ("", nil), ("  \n ", nil),
    ]
    for (text, expected) in table {
        let n = PageText.near(text)
        #expect(n == expected, "\(text)")
        #expect((n?.count ?? 0) <= PageText.nearLimit)
    }
}

@Test func requestRendersNearAndGivesOnlyAPageReadingTheLongLimit() {
    let page = "page: " + String(repeating: "p", count: 3000)
    let clip = "clipboard: " + String(repeating: "c", count: 3000)
    var o = ScreenObservation(app: "Chrome", windowTitle: "Schedule", url: nil, mode: .command, overlay: "none", elements: [
        ObservedElement(number: 1, role: "link", title: "Watch", states: ["focused"], near: "Raptors vs Celtics 7:30 PM"),
        ObservedElement(number: 2, role: "link", title: "Watch", value: "v", near: "a\nb \"q\""),
        ObservedElement(number: 3, role: "link", title: "Home"),
    ])
    o.readings = [page, clip]
    let text = ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "g", step: 2, maxSteps: 5, history: [], observation: o))
    #expect(text.contains(#"  1 [link] Watch (focused) near: "Raptors vs Celtics 7:30 PM""#))
    #expect(text.contains(#"  2 [link] Watch near: "a b 'q'" = "v""#))
    #expect(text.contains("  3 [link] Home\n"))
    #expect(text.contains("  " + page + "\n"))
    #expect(!text.contains(clip) && text.contains(String(clip.prefix(300)) + "\n"))
}

@Test func readPageDecodesWithNoFields() throws {
    let step = try IntentDecoder.step(fromPayloadText: #"{"intent":"x","status":"continue","actions":[{"kind":"read_page"}]}"#)
    #expect(step.actions == [.readPage])
}
