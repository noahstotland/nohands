import Testing
@testable import NoHandsCore

@Test func playbooksMatchOnTheGoalsSiteNameOrThePagesExactHost() {
    let cases: [(goal: String, url: String?, names: [String])] = [
        ("turn on the latest outdoor boys youtube video", nil, ["YouTube"]),
        ("play it on you tube", nil, ["YouTube"]),
        ("open youtube's trending page", nil, ["YouTube"]),
        ("play it on youtube\u{2019}s home", nil, ["YouTube"]),
        ("open the finder window", nil, []),
        ("open google chrome", nil, []),
        ("search google maps for pizza", nil, []),
        ("google cats", nil, ["Google"]),
        ("open google chrome and google cats", nil, ["Google"]),
        ("open notyoutube", nil, []),
        ("click the first one", "https://www.youtube.com/watch?v=x", ["YouTube"]),
        ("click the first one", "https://youtube.com.evil.example/", []),
        ("click the first one", "https://evil.example/youtube.com", []),
        ("click the first one", "https://docs.google.com/document/d/1", []),
        ("click the first one", "https://mail.google.com/", []),
        ("click the first one", "https://aws.amazon.com/", []),
        ("click the first one", "not a url", []),
        ("open youtube", "https://m.youtube.com/", ["YouTube"]),
        ("open youtube", "https://www.reddit.com/r/swift", ["YouTube", "Reddit"]),
        ("amazon prime video", nil, []),
        ("find a cable on amazon", nil, ["Amazon"]),
        ("look up turing on wikipedia", nil, ["Wikipedia"]),
    ]
    for c in cases {
        #expect(SitePlaybooks.matching(goal: c.goal, url: c.url).map(\.name) == c.names, "\(c.goal) @ \(c.url ?? "-")")
    }
}

@Test func theRoutesSitBeforeTheScreenInTheRequestAndNeverInTheFewShotExamples() {
    func message(_ goal: String) -> String {
        ClaudeRequestBuilder.userMessage(request: StepRequest(
            goal: goal, step: 1, maxSteps: 12, history: [], observation: ScreenObservation(app: "Finder", mode: .command)))
    }
    let youtube = message("play bohemian rhapsody on youtube")
    let routes = youtube.range(of: "Site routes (written by NoHands, not by the page; follow one when it fits the goal):\nYouTube:\n  ")
    #expect(routes != nil && routes!.lowerBound < youtube.range(of: "\nApp: Finder")!.lowerBound)
    #expect(!message("move the window left").contains("Site routes"))
    for harness in [HarnessKind.native, .agentDesktop] {
        #expect(IntentExamples.turns(for: harness).allSatisfy { !$0.user.contains("Site routes") })
    }
}
