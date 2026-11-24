import Testing
@testable import NoHandsCore

@Test func spokenFeedbackWording() {
    typealias C = FeedbackCue
    let cases: [(name: String, cue: C, outcomes: String?, all: String?)] = [
        ("done with detail", .status(.done("done · open the menu (2 steps)"), carriesPrivateText: false), "Done: open the menu.", "Done: open the menu."),
        ("one step", .status(.done("done · open the menu (1 step)"), carriesPrivateText: false), "Done: open the menu.", "Done: open the menu."),
        ("macro", .status(.done("done · 3 steps"), carriesPrivateText: false), "Done.", "Done."),
        ("stuck", .status(.failed("stuck: no Raptors game listed (5 steps)"), carriesPrivateText: false), "Stuck: no Raptors game listed.", "Stuck: no Raptors game listed."),
        ("timed out", .status(.failed("timed out"), carriesPrivateText: false), "Timed out.", "Timed out."),
        ("private done", .status(.done("done · the clipboard says hello (1 step)"), carriesPrivateText: true), "Done.", "Done: the clipboard says hello."),
        ("private rewrite", .status(.done("Fix the typo in the…"), carriesPrivateText: true), "Done.", "Fix the typo in the."),
        ("private stuck", .status(.failed("stuck: the field holds secret (2 steps)"), carriesPrivateText: true), "Stuck.", "Stuck: the field holds secret."),
        ("private other failure", .status(.failed("timed out"), carriesPrivateText: true), "Failed.", "Timed out."),
        ("empty detail", .status(.done(""), carriesPrivateText: false), nil, nil),
        ("question", .question("which one, the 7 pm or the 10 pm"), nil, "Which one, the 7 pm or the 10 pm?"),
        ("question clipped", .question("which one…"), nil, "Which one?"),
        ("confirm", .confirm(verb: "send"), nil, "Say yes to send."),
    ]
    for c in cases {
        #expect(SpokenFeedback.line(for: c.cue, level: .outcomes) == c.outcomes, "\(c.name) outcomes")
        #expect(SpokenFeedback.line(for: c.cue, level: .all) == c.all, "\(c.name) all")
        #expect(SpokenFeedback.line(for: c.cue, level: .off) == nil, "\(c.name) off")
    }
}

@Test func spokenFeedbackIsSilentForProgressStatuses() {
    let silent: [PromptStatus] = [.listening, .heard, .held, .running("step 2 · open the menu"), .stopped("stopped"), .dropped("late"), .ignored("not a command")]
    for status in silent {
        for private_ in [true, false] {
            for level in SpeakLevel.allCases {
                #expect(SpokenFeedback.line(for: .status(status, carriesPrivateText: private_), level: level) == nil, "\(status) \(level)")
            }
        }
    }
}

@Test func spokenFeedbackCutsLongLinesOnAWord() throws {
    let long = (1...200).map { "word\($0)" }.joined(separator: " ")
    for private_ in [true, false] {
        let line = try #require(SpokenFeedback.line(for: .status(.done(long), carriesPrivateText: private_), level: .all))
        #expect(line.count <= SpokenFeedback.maxSpoken && line.hasSuffix("."))
        let spoken = line.dropLast().split(separator: " ").map { $0.lowercased() }
        #expect(spoken == Array(long.split(separator: " ").prefix(spoken.count)).map(String.init), "ends on a whole word")
        #expect(spoken.count < 200 && spoken.count > 30)
    }
}
