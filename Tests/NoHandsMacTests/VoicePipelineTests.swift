import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

private struct NullTranscriber: Transcribing { func transcribe(_ samples: [Float]) async throws -> String { "" } }

/// Returns `scripted[n-1]` (the last one repeats) when scripted, else a `done` step carrying `result`.
private final class FakeResolver: IntentResolving, @unchecked Sendable {
    var result: Result<[Action], IntentError> = .success([])
    var scripted: [IntentStep] = []
    var calls = 0
    var lastContext: IntentContext?
    /// Called with the 1-based call number before the step is returned.
    var onResolve: (@Sendable (Int) async -> Void)?
    func resolve(_ request: StepRequest) async throws -> IntentStep {
        calls += 1
        let n = calls
        lastContext = IntentContext(frontmostApp: request.observation.app, mode: request.observation.mode,
                                    labeledElements: request.observation.elements.map { ($0.number, $0.title) },
                                    overlay: request.observation.overlay)
        await onResolve?(n)
        if !scripted.isEmpty { return scripted[min(n - 1, scripted.count - 1)] }
        return IntentStep(intent: "", status: .done, actions: try result.get())
    }
}

private let reloadButton = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Reload", role: "AXButton")

@MainActor private struct Rig {
    var pipeline: VoicePipeline
    var input: FakeInput
    var ax: FakeElements
    var overlay: FakeOverlay
    var resolver: FakeResolver?
    var typed: [String] { input.calls.filter { $0.hasPrefix("type:") } }
}

@MainActor private func rig(withResolver: Bool = true) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: AppConfig(), frontTimeout: .milliseconds(100))
    let resolver = withResolver ? FakeResolver() : nil
    let config = AppConfig()
    let observer = ScreenObserver(ax: ax, maxElements: config.maxObservedElements)
    let runner = resolver.map {
        TaskRunner(config: config, resolver: $0, executor: executor, observer: observer, overlay: overlay, sleep: { _ in })
    }
    let p = VoicePipeline(config: config, transcriber: NullTranscriber(), resolver: resolver,
                          executor: executor, overlay: overlay, ax: ax, observer: observer, taskRunner: runner)
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
    await r.pipeline.waitForTask()
    #expect(r.input.calls == ["click:140,115"])
    #expect(r.resolver?.lastContext?.overlay == "none")
    #expect(r.pipeline.lastTaskOutcome == .done(""))
}

@MainActor @Test func llmLabelClickWithGridShowingStillHitsElement() async {
    let r = rig()
    r.ax.elements = [reloadButton]
    r.overlay.state = .grid(GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)))
    r.resolver?.result = .success([.click(.label(1), button: .left, count: 1)])
    await r.pipeline.handle(transcript: "reload the page", trace: trace())
    await r.pipeline.waitForTask()
    #expect(r.input.calls == ["click:140,115"])        // grid cell 1 would be 50,50
    #expect(r.resolver?.lastContext?.overlay == "grid")
}

@MainActor @Test func llmFailuresShowHudText() async {
    let cases: [(IntentError, String?)] = [
        (.timeout, "timed out"), (.network(URLError(.notConnectedToInternet)), "no network"),
        (.decode(.refusal), "didn't catch that"), (.cancelled, "stopped"),
    ]
    for (error, hud) in cases {
        let r = rig()
        r.resolver?.result = .failure(error)
        await r.pipeline.handle(transcript: "make it bigger", trace: trace())
        await r.pipeline.waitForTask()
        #expect(r.overlay.huds == ["make it bigger", hud])   // the runner shows the finish HUD once
        #expect(r.input.calls == ["releaseAll"])               // the runner's safety release; nothing executed
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
    await r.pipeline.waitForTask()
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
    r.resolver?.onResolve = { _ in await MainActor.run { pipeline.pause() } }   // pause lands while resolving
    await r.pipeline.handle(transcript: "reload the page", trace: trace())
    await r.pipeline.waitForTask()
    #expect(!r.input.calls.contains { $0.hasPrefix("click") })
    #expect(r.input.calls.allSatisfy { $0 == "releaseAll" })   // pause()'s and the runner's safety releases only
    #expect(r.pipeline.lastTaskOutcome == .stopped)
}

@MainActor @Test func pauseReleasesInputAndHidesOverlay() async {
    let r = rig()
    r.overlay.state = .grid(GridModel(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)))
    r.pipeline.stop()
    #expect(r.input.calls == ["releaseAll"])
    #expect(r.overlay.state == .none)
}

// MARK: - tasks run without blocking the consumer

/// A one-shot signal a fake resolver can await (ends early if the awaiting task is cancelled).
private struct Gate: Sendable {
    let stream: AsyncStream<Void>
    let cont: AsyncStream<Void>.Continuation
    init() { (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded) }
    func open() { cont.yield() }
    func wait() async { for await _ in stream { break } }
}

private func step(_ intent: String, _ status: StepStatus, _ actions: [Action] = []) -> IntentStep {
    IntentStep(intent: intent, status: status, actions: actions)
}

@MainActor @Test func stopPhraseCancelsRunningTask() async {
    let r = rig()
    let entered = Gate(), release = Gate()
    r.resolver?.scripted = [step("type a", .continue, [.typeText("a")]), step("type b", .done, [.typeText("b")])]
    r.resolver?.onResolve = { n in if n == 2 { entered.open(); await release.wait() } }
    await r.pipeline.handle(transcript: "find the newest video", trace: trace())
    #expect(r.pipeline.isTaskActive)                       // handle returned while the task runs
    await entered.wait()                                   // step 2 is resolving
    await r.pipeline.handle(transcript: "stop", trace: trace())
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped)
    #expect(r.typed == ["type:a"])                         // step 2's actions never executed
    #expect(r.input.calls.contains("releaseAll"))
    #expect(r.overlay.huds.last == PipelineText.stopped)
    #expect(!r.pipeline.isTaskActive)
}

@MainActor @Test func utteranceDuringTaskIsHeldThenRun() async {
    let r = rig()
    let entered = Gate(), release = Gate()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    r.resolver?.onResolve = { _ in entered.open(); await release.wait() }
    await r.pipeline.handle(transcript: "find the newest video", trace: trace())
    await entered.wait()
    await r.pipeline.handle(transcript: "scroll down", trace: trace())   // held, then replaced (newest wins)
    await r.pipeline.handle(transcript: "click", trace: trace())
    #expect(r.input.calls.isEmpty)                         // nothing runs concurrently with the task
    #expect(r.overlay.huds.filter { $0 == PipelineText.busySayStop }.count == 2)
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .done("type a"))
    #expect(r.input.calls == ["type:a", "click:10,20"])    // the task first, then only the newest held job
    #expect(r.resolver?.calls == 1)
}

@MainActor @Test func grammarCommandsUnaffected() async {
    let r = rig()
    await r.pipeline.handle(transcript: "click", trace: trace())
    #expect(!r.pipeline.isTaskActive)                      // grammar runs inline, no task
    #expect(r.input.calls == ["click:10,20"])
    #expect(r.resolver?.calls == 0)
    r.overlay.state = .grid(GridModel(bounds: CGRect(x: 0, y: 0, width: 100, height: 100)))
    await r.pipeline.handle(transcript: "cancel", trace: trace())   // no task: still the grammar's hide command
    #expect(r.overlay.state == .none)
    #expect(r.resolver?.calls == 0)
    #expect(!r.overlay.huds.contains(PipelineText.stopped))
}

@MainActor @Test func pauseCancelsActiveTaskAndDropsHeldJob() async {
    let r = rig()
    let entered = Gate()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    r.resolver?.onResolve = { _ in entered.open(); await Gate().wait() }   // blocks until cancelled
    await r.pipeline.handle(transcript: "find the newest video", trace: trace())
    await entered.wait()
    await r.pipeline.handle(transcript: "click", trace: trace())          // held
    r.pipeline.pause()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped)
    #expect(r.input.calls.allSatisfy { $0 == "releaseAll" })             // neither the task nor the held click ran
}

@Test func outcomeHudText() {
    #expect(PipelineText.hud(for: TaskOutcome.done("")) == "done")
    #expect(PipelineText.hud(for: TaskOutcome.done("opened it")) == "done · opened it")
    #expect(PipelineText.hud(for: TaskOutcome.stuck("no button")) == "stuck: no button")
    #expect(PipelineText.hud(for: TaskOutcome.ignored) == PipelineText.didntCatch)
    #expect(PipelineText.hud(for: TaskOutcome.stopped) == "stopped")
    #expect(PipelineText.hud(for: TaskOutcome.failed("timed out")) == "timed out")
    #expect(PipelineText.busySayStop == "busy — say stop to cancel")
}

@MainActor @Test func idleStopPhraseIsIgnored() async {
    let r = rig()
    for phrase in ["stop", "never mind", "halt"] {
        await r.pipeline.handle(transcript: phrase, trace: trace())
        #expect(!r.pipeline.isTaskActive)
    }
    #expect(r.resolver?.calls == 0)
    #expect(r.overlay.huds.isEmpty)
    #expect(r.input.calls.isEmpty)
}
