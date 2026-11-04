import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

private struct NullTranscriber: Transcribing { func transcribe(_ samples: [Float]) async throws -> String { "" } }

private final class FakeResolver: IntentResolving, @unchecked Sendable {
    var result: Result<[Action], IntentError> = .success([])
    var lastContext: IntentContext?
    var onResolve: (@Sendable () async -> Void)?
    func resolve(_ transcript: String, context: IntentContext) async throws -> [Action] {
        lastContext = context
        await onResolve?()
        return try result.get()
    }
}

private let reloadButton = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Reload", role: "AXButton")

@MainActor private struct Rig {
    var pipeline: VoicePipeline
    var input: FakeInput
    var ax: FakeElements
    var overlay: FakeOverlay
    var resolver: FakeResolver?
}

@MainActor private func rig(withResolver: Bool = true) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: AppConfig(), frontTimeout: .milliseconds(100))
    let resolver = withResolver ? FakeResolver() : nil
    let p = VoicePipeline(config: AppConfig(), transcriber: NullTranscriber(), resolver: resolver,
                          executor: executor, overlay: overlay, ax: ax)
    return Rig(pipeline: p, input: input, ax: ax, overlay: overlay, resolver: resolver)
}

private func trace(age: Duration = .zero) -> LatencyTrace {
    var t = LatencyTrace()
    t.speechEnd = ContinuousClock.now.advanced(by: .zero - age)
    t.asrDone = .now
    return t
}

@MainActor @Test func grammarUtteranceExecutes() async {
    let r = rig()
    await r.pipeline.handle(transcript: "click", trace: trace())
    #expect(r.input.calls == ["click:10,20"])
    #expect(r.overlay.huds == ["click"])
}

@MainActor @Test func llmLabelClickEndToEnd() async {
    let r = rig()
    r.ax.elements = [reloadButton]
    r.ax.front = "Safari"
    r.resolver?.result = .success([.click(.label(1), button: .left, count: 1)])
    await r.pipeline.handle(transcript: "reload the page", trace: trace())
    #expect(r.input.calls == ["click:140,115"])
    #expect(r.resolver?.lastContext?.overlay == "none")
}

@MainActor @Test func llmLabelClickWithGridShowingStillHitsElement() async {
    let r = rig()
    r.ax.elements = [reloadButton]
    r.overlay.state = .grid(GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)))
    r.resolver?.result = .success([.click(.label(1), button: .left, count: 1)])
    await r.pipeline.handle(transcript: "reload the page", trace: trace())
    #expect(r.input.calls == ["click:140,115"])        // grid cell 1 would be 50,50
    #expect(r.resolver?.lastContext?.overlay == "grid")
}

@MainActor @Test func llmFailuresShowHudText() async {
    let cases: [(IntentError, String?)] = [
        (.timeout, "timed out"), (.network(URLError(.notConnectedToInternet)), "no network"),
        (.decode(.refusal), "didn't catch that"), (.cancelled, nil),
    ]
    for (error, hud) in cases {
        let r = rig()
        r.resolver?.result = .failure(error)
        await r.pipeline.handle(transcript: "make it bigger", trace: trace())
        #expect(r.overlay.huds == ["make it bigger"] + (hud.map { [$0] } ?? []))
        #expect(r.input.calls.isEmpty)
    }
}

@MainActor @Test func noResolverShowsHintOnceThenDidntCatch() async {
    let r = rig(withResolver: false)
    await r.pipeline.handle(transcript: "make it bigger", trace: trace())
    await r.pipeline.handle(transcript: "make it smaller", trace: trace())
    #expect(r.overlay.huds == ["make it bigger", PipelineText.llmOff, "make it smaller", "didn't catch that"])
}

@MainActor @Test func staleJobIsDroppedWithBusyHud() async {
    let r = rig()
    await r.pipeline.handle(transcript: "click", trace: trace(age: .seconds(9)))
    #expect(r.input.calls.isEmpty)
    #expect(r.overlay.huds == ["skipped (busy)"])
}

@MainActor @Test func sleepIgnoresSilently() async {
    let r = rig()
    await r.pipeline.handle(transcript: "go to sleep", trace: trace())
    #expect(r.pipeline.mode == .sleep)
    r.overlay.huds.removeAll()
    await r.pipeline.handle(transcript: "click", trace: trace())
    await r.pipeline.handle(transcript: "make it bigger", trace: trace())
    #expect(r.overlay.huds.isEmpty)
    #expect(r.input.calls.isEmpty)
}

@MainActor @Test func llmSetModeRoundTripsThroughModeMachine() async {
    let r = rig()
    var seen: [Mode] = []
    r.pipeline.onStatus = { mode, _ in seen.append(mode) }
    r.resolver?.result = .success([.setMode(.dictation)])
    await r.pipeline.handle(transcript: "let me write something", trace: trace())
    #expect(r.pipeline.mode == .dictation)
    #expect(seen.contains(.dictation))
    await r.pipeline.handle(transcript: "hello there", trace: trace())   // now typed, not sent to the LLM
    #expect(r.input.calls == ["type:Hello there"])
}

@MainActor @Test func jobInFlightAtPauseNeverExecutes() async {
    let r = rig()
    r.ax.elements = [reloadButton]
    r.resolver?.result = .success([.click(.label(1), button: .left, count: 1)])
    let pipeline = r.pipeline
    r.resolver?.onResolve = { await MainActor.run { pipeline.pause() } }   // pause lands while resolving
    await r.pipeline.handle(transcript: "reload the page", trace: trace())
    #expect(r.input.calls == ["releaseAll"])   // only pause()'s safety release; no click
}

@MainActor @Test func pauseReleasesInputAndHidesOverlay() async {
    let r = rig()
    r.overlay.state = .grid(GridModel(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)))
    r.pipeline.stop()
    #expect(r.input.calls == ["releaseAll"])
    #expect(r.overlay.state == .none)
}
