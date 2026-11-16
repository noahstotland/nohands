import Testing
import Foundation
@testable import NoHandsCore

private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
private func route(_ goal: String, host: String? = nil, at seconds: Double = 0, steps: [RouteStep] = []) -> Route {
    Route(goal: goal, host: host, steps: steps, savedAt: epoch + seconds)
}

@Test func aGoalFindsTheRouteThatFitsItAndTheHostRuleKeepsOtherSitesOut() {
    let raptors = route("open the raptors game on espn", host: "espn.com")
    let lofi = route("play lofi on youtube", host: "youtube.com")
    // (goal, page host, routes, the matched route's goal)
    let table: [(String, String?, [Route], String?)] = [
        ("open the raptors game on espn", "espn.com", [lofi, raptors], raptors.goal),
        ("open the lakers game on espn", nil, [lofi, raptors], raptors.goal),            // 3 of 4 words
        ("raptors game", nil, [raptors], nil),                                            // 2 of 4 words: under 0.6
        ("open espn", nil, [raptors], nil),                                               // under 0.6
        ("raptors", nil, [route("raptors")], nil),                                        // one shared word is never enough
        ("open the raptors game on espn", "youtube.com", [raptors], raptors.goal),        // the goal names the site
        ("play lofi", "www.espn.com", [lofi], nil),                                       // another site, and not named
        ("play lofi on youtube", "youtube.com", [lofi], lofi.goal),
        ("play some lofi tunes", "espn.com", [route("play some lofi tunes", host: nil)], "play some lofi tunes"),   // route has no host
        ("open the raptors game", "en.espn.com", [route("open raptors game", host: "espn.com")], nil),
    ]
    for (goal, host, routes, want) in table {
        #expect(RouteMemory.match(goal: goal, currentHost: host, in: routes)?.goal == want, "\(goal) @ \(host ?? "-")")
    }
    // The best score wins; a tie goes to the newest.
    let best = [route("open raptors game on espn today", at: 9), route("open raptors game on espn", at: 1)]
    #expect(RouteMemory.match(goal: "open raptors game on espn", currentHost: nil, in: best)?.savedAt == epoch + 1)
    let tie = [route("open raptors game", at: 5), route("open raptors game!", at: 2), route("open game raptors", at: 8)]
    #expect(RouteMemory.match(goal: "open raptors game", currentHost: nil, in: tie)?.savedAt == epoch + 8)
}

@Test func stepsKeepNamesAndNeverTypedText() throws {
    let url = try #require(URL(string: "https://www.espn.com/nba/scoreboard/?q=secret#frag"))
    let history = [
        StepRecord(intent: "open the scoreboard\nnow", actions: [.openURL(url, app: nil), .wait(ms: 500)]),
        StepRecord(intent: "open the game", actions: [.click(.label(5), button: .left, count: 1), .click(.label(9), button: .left, count: 1),
                                                       .click(.point(CGPoint(x: 3, y: 4)), button: .left, count: 1)]),
        StepRecord(intent: "boom", actions: [.click(.label(5), button: .left, count: 1)], failure: "not found"),
        StepRecord(intent: "search it", actions: [.typeInto(.label(5), "hunter2"), .search("hunter2"), .searchSite("hunter2", site: "youtube.com"),
                                                   .setValue(.named("x"), "hunter2"), .clipboardSet("hunter2"), .typeText("hunter2"),
                                                   .menuItem("File > Save"), .openApp("Safari"), .selectTab(3), .findOnPage("hunter2", movePointer: false)]),
        StepRecord(intent: "Which stream?", actions: [], userAnswer: "the hunter2 one"),
    ]
    let names: [[Int: String]] = [[:], [5: "Raptors \"vs\" Lakers", 9: ""], [:], [5: "Search"]]
    let steps = RouteMemory.steps(from: history, names: names)
    #expect(steps.map(\.intent) == ["open the scoreboard now", "open the game", "search it", "Which stream?"])
    #expect(steps[0].actions == ["open_url espn.com/nba/scoreboard", "wait"])
    #expect(steps[1].actions == ["click \"Raptors 'vs' Lakers\"", "click", "click"])
    #expect(steps[2].actions == ["type_into", "search", "search_site youtube", "set_value", "clipboard_set", "type_text",
                                 "menu_item \"File > Save\"", "open_app \"Safari\"", "select_tab", "find_on_page"])
    #expect(steps[3].asked && steps[3].actions.isEmpty)
    #expect(!String(decoding: try JSONEncoder().encode(steps), as: UTF8.self).contains("hunter2"))
}

@Test func intentsNeverCarryTypedTextAnswersOrLabelNumbers() {
    let history = [
        StepRecord(intent: "Type the text \"Hunter2\" and press Return", actions: [.typeText("hunter2")]),
        StepRecord(intent: "Search for 'cats on a wall' now", actions: [.search("cats on a wall")]),
        StepRecord(intent: "Which stream?", actions: [], userAnswer: "Sky Sports"),
        StepRecord(intent: "Click the sky sports stream, visible element 6.", actions: [.click(.label(6), button: .left, count: 1)]),
        StepRecord(intent: "Open the 'cats on a wall' result, user's page", actions: [.click(.label(6), button: .left, count: 1)]),
        StepRecord(intent: "Typed HUNTER2 into the field", actions: [.pressKey(KeyChord(.return, []))]),
    ]
    let intents = RouteMemory.steps(from: history, names: [[:], [:], [:], [6: "Stream"], [6: "Result"], [:]]).map(\.intent)
    #expect(intents == ["Type the text … and press Return", "Search for … now", "Which stream?", "Click the … stream, visible the element.", "Open the … result, user's page", "Typed … into the field"])
}

@Test func theFileRoundTripsAndABadOneIsEmptyNotAnError() throws {
    let a = route("open raptors game", host: "espn.com", steps: [RouteStep(intent: "go", actions: ["click \"x\""], asked: true)])
    #expect(RouteMemory.decode(try RouteMemory.encoded([a])) == [a])
    let table: [(String?, Int)] = [
        (nil, 0), ("", 0), ("{", 0), ("[]", 0), (#"{"version":2,"routes":[]}"#, 0), (#"{"routes":[]}"#, 0), (#"{"version":1,"routes":5}"#, 0),
        (#"{"version":1,"routes":[7,{"goal":"x"},{"goal":"g","host":null,"steps":[],"savedAt":"2027-01-15T08:00:00Z"}]}"#, 1),
    ]
    for (json, count) in table { #expect(RouteMemory.decode(json.map { Data($0.utf8) }).count == count, "\(json ?? "nil")") }
    // The file is untrusted: long text is cut and a host is normalized.
    let long = #"{"version":1,"routes":[{"goal":"\#(String(repeating: "g", count: 400))","host":"WWW.Espn.com","steps":[{"intent":"\#(String(repeating: "i", count: 200))","actions":["a\nb"],"asked":false}],"savedAt":"2027-01-15T08:00:00Z"}]}"#
    let loaded = try #require(RouteMemory.decode(Data(long.utf8)).first)
    #expect(loaded.goal.count == 300 && loaded.host == "espn.com" && loaded.steps[0].intent.count == 80 && loaded.steps[0].actions == ["a b"])
}

@Test func savingReplacesTheSameGoalAndHostAndKeepsTheNewest50() {
    let old = [route("Open the game!", host: "espn.com", at: 1), route("open the game", host: "nba.com", at: 2)]
    let saved = RouteMemory.saving(route("open the game", host: "espn.com", at: 3), into: old)
    #expect(saved.map(\.savedAt) == [epoch + 2, epoch + 3])      // same goal key and host replaced; another host kept
    let many = (0..<50).map { route("goal \($0)", at: Double($0)) }
    let capped = RouteMemory.saving(route("new goal", at: 99), into: many)
    #expect(capped.count == 50 && capped.first?.goal == "goal 1" && capped.last?.goal == "new goal")
    #expect(RouteMemory.host(of: "https://www.ESPN.com/nba") == "espn.com" && RouteMemory.host(of: "youtube.com/watch?v=1") == "youtube.com")
    #expect(RouteMemory.host(of: "file:///tmp/a") == nil && RouteMemory.host(of: nil) == nil)
}
