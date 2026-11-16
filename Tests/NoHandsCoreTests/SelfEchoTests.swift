import Testing
@testable import NoHandsCore

@Test func selfEchoDropsOnlyTheLineHeardInItsWindow() {
    let t0 = ContinuousClock.now
    func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }
    let line = "Which one, the 7 pm or the 10 pm?"
    let finished = SpokenLine(text: line, start: at(0), end: at(3000))
    let speaking = SpokenLine(text: line, start: at(0), end: nil)
    let cases: [(name: String, transcript: String, end: Int, spoken: SpokenLine?, echo: Bool)] = [
        ("inside the window", "which one the 7 pm or the 10 pm", 2500, finished, true),
        ("within the tail", "which one the 7 pm or the 10 pm", 3900, finished, true),
        ("after the tail", "which one the 7 pm or the 10 pm", 4100, finished, false),
        ("before the line began", "which one the 7 pm or the 10 pm", -10, finished, false),
        ("still speaking, open window", "which one the 7 pm or the 10 pm", 60_000, speaking, true),
        ("different command", "open safari and go to the news", 2500, finished, false),
        ("mostly overlapping", "which one the 7 pm please", 2500, finished, true),
        ("a few shared words", "go to the 10 pm showing", 2500, finished, false),
        ("short transcript, all words in line", "the 10 pm", 2500, finished, true),
        ("short transcript, one word not in line", "10 pm yes", 2500, finished, false),
        ("one word, in the line", "which", 2500, finished, true),
        ("one word, not in the line", "yes", 2500, finished, false),
        ("nothing spoken", "which one the 7 pm or the 10 pm", 2500, nil, false),
        ("empty transcript", "  ", 2500, finished, false),
    ]
    for c in cases {
        #expect(SelfEcho.isEcho(transcript: c.transcript, utteranceEnd: at(c.end), spoken: c.spoken) == c.echo, "\(c.name)")
    }
}
