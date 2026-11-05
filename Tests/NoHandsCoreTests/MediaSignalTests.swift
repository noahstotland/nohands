import Testing
import Foundation
@testable import NoHandsCore

@Test func controlReadsOnlyExactPlayerButtons() {
    let table: [(role: String, name: String, value: String?, want: MediaControl?)] = [
        ("button", "Pause (k)", nil, .pause), ("AXButton", "Play", nil, .play), ("button", " Play (space) ", nil, .play),
        ("button", "Pause video", nil, .pause), ("switch", "Play button.", nil, .play),
        ("button", "Play/Pause", "playing", .pause), ("button", "Play/Pause", "paused", .play), ("button", "Play/Pause", nil, nil),
        ("button", "Play all", nil, nil), ("link", "Play", nil, nil), ("button", "Playlist", nil, nil),
        ("button", "Play next", nil, nil), ("heading", "Pause", nil, nil), ("button", "Display", nil, nil),
    ]
    for t in table {
        #expect(MediaSignal.control(role: t.role, name: t.name, value: t.value) == t.want, "\(t.role) \(t.name) \(t.value ?? "-")")
    }
}

@Test func stateTrustsControlsBeforeAudio() {
    let table: [(controls: [MediaControl], audio: Bool, want: MediaState)] = [
        ([.pause], false, .playing), ([.pause, .play], false, .playing), ([.play], false, .paused),
        ([.play], true, .paused), ([], true, .playing), ([], false, .none),
    ]
    for t in table { #expect(MediaSignal.state(controls: t.controls, audioPlaying: t.audio) == t.want, "\(t.controls) \(t.audio)") }
    // Audio is only asked when no element is a control.
    let play = UIElementInfo(id: 1, frame: .zero, title: "Play", role: "AXButton")
    #expect(MediaSignal.state(elements: [play], audioPlaying: { Issue.record("asked"); return true }) == .paused)
    #expect(MediaSignal.state(elements: [], audioPlaying: { true }) == .playing)
}

@Test func wantsPlaybackMatchesWholeWords() {
    let table: [(String, Bool)] = [
        ("turn on the latest outdoor boys video", true), ("put the video on", true), ("watch veritasium", true),
        ("play some jazz", true), ("listen to the podcast", true), ("turn the video on", true),
        ("display settings", false), ("replay", false), ("turn off wifi", false), ("is it playing", false),
        ("open youtube", false),
    ]
    for (goal, want) in table { #expect(MediaSignal.wantsPlayback(goal: goal) == want, Comment(rawValue: goal)) }
}

@Test func mediaLineAppearsOnlyWhenObserved() {
    var o = ScreenObservation(app: "Safari", mode: .command)
    func text() -> String { ClaudeRequestBuilder.userMessage(request: StepRequest(goal: "g", step: 1, maxSteps: 3, history: [], observation: o)) }
    #expect(!text().contains("Media:"))
    o.media = .paused
    #expect(text().contains("Harness: native\nMedia: paused\nVisible elements:"))
    var other = o
    other.media = .playing
    #expect(!Settle.same(o, other))
}

@Test func mediaPlayingWaitDecodesWithTheUsualTimeouts() throws {
    func w(_ f: String) throws -> [Action] {
        try IntentDecoder.actions(fromPayloadText: #"{"intent":"","status":"continue","actions":[{"kind":"wait","wait_for":"media_playing"\#(f)}]}"#)
    }
    #expect(try w("") == [.waitFor(.mediaPlaying, timeoutMs: 5000)])
    #expect(try w(#","timeout_ms":100"#) == [.waitFor(.mediaPlaying, timeoutMs: 500)])
    #expect(try w(#","timeout_ms":99999"#) == [.waitFor(.mediaPlaying, timeoutMs: 30000)])
    #expect(DesktopWaitKind.allCases.map(\.rawValue).contains("media_playing"))
}

@Test func playingQuestionsAreGrammarCommands() {
    for phrase in ["is it playing", "Is the video playing?", "is anything playing"] {
        #expect(CommandGrammar().parse(phrase) == [.checkMedia], Comment(rawValue: phrase))
    }
}
