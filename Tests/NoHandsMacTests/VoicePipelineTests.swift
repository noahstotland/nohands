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
    var requests: [StepRequest] = []
    var lastContext: IntentContext?
    /// Called with the 1-based call number before the step is returned.
    var onResolve: (@Sendable (Int) async -> Void)?
    func resolve(_ request: StepRequest) async throws -> IntentStep {
        calls += 1
        requests.append(request)
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
    var executor: ActionExecutor
    var observer: ScreenObserver
    var runner: TaskRunner?
    var typed: [String] { input.calls.filter { $0.hasPrefix("type:") } }
}

@MainActor private func rig(withResolver: Bool = true, attentionWord: String = "", macros: String = "{}",
                            commandLog: CommandLogStore? = nil, routes: FakeRouteStore? = nil,
                            sleep: @escaping @Sendable (Duration) async -> Void = { _ in }) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: AppConfig(), frontTimeout: .milliseconds(100))
    let resolver = withResolver ? FakeResolver() : nil
    var config = try! AppConfig.load(from: Data(#"{"macros":\#(macros)}"#.utf8), environment: [:])
    config.attentionWord = attentionWord
    let observer = ScreenObserver(ax: ax, maxElements: config.maxObservedElements)
    let runner = resolver.map {
        TaskRunner(config: config, resolver: $0, executor: executor, observer: observer, overlay: overlay, sleep: sleep, routes: routes)
    }
    let p = VoicePipeline(config: config, transcriber: NullTranscriber(), resolver: resolver,
                          executor: executor, overlay: overlay, ax: ax, observer: observer, taskRunner: runner,
                          commandLog: commandLog, routes: routes)
    p.macroStepPause = .zero
    return Rig(pipeline: p, input: input, ax: ax, overlay: overlay, resolver: resolver, executor: executor, observer: observer, runner: runner)
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
    #expect(r.overlay.reports.map(\.text) == ["click", "click"])   // one row: heard, then done
    #expect(r.overlay.statuses == ["heard", "done"])
    #expect(r.overlay.huds.isEmpty)
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
    let id = r.overlay.reports.first?.id
    #expect(!r.overlay.trails.isEmpty && r.overlay.trails.allSatisfy { $0.id == id })   // the trail rides on the prompt's row
    #expect(r.overlay.trails.last?.trail.steps.map(\.state) == [.done])
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
        #expect(r.overlay.statuses == ["heard", hud])        // the runner's finish line lands on the prompt's row
        #expect(Set(r.overlay.reports.map(\.id)).count == 1)
        #expect(r.input.calls == ["releaseAll"])               // the runner's safety release; nothing executed
    }
}

@MainActor @Test func noResolverShowsHintOnceThenDidntCatch() async {
    let r = rig(withResolver: false)
    await r.pipeline.handle(transcript: "make it bigger", trace: trace())
    await r.pipeline.handle(transcript: "make it smaller", trace: trace())
    #expect(r.overlay.statuses == ["heard", PipelineText.llmOff, "heard", "didn't catch that"])
}

@MainActor @Test func staleJobIsDroppedWithBusyHud() async {
    let r = rig()
    await r.pipeline.handle(transcript: "click", trace: trace(age: .seconds(9)))
    #expect(r.input.calls.isEmpty)
    #expect(r.overlay.statuses == ["skipped (busy)"])
}

@MainActor @Test func sleepIgnoresSilently() async {
    let r = rig()
    await r.pipeline.handle(transcript: "go to sleep", trace: trace())
    #expect(r.pipeline.mode == .sleep)
    r.overlay.reports.removeAll()
    await r.pipeline.handle(transcript: "click", trace: trace())
    await r.pipeline.handle(transcript: "make it bigger", trace: trace())
    #expect(r.overlay.reports.isEmpty && r.overlay.huds.isEmpty)
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
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    #expect(r.pipeline.isTaskActive)                       // handle returned while the task runs
    await entered.wait()                                   // step 2 is resolving
    await r.pipeline.handle(transcript: "stop", trace: trace())
    #expect(r.input.calls.contains("releaseAll"))          // the stop let go of a held button at once, before the runner unwinds
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped)
    #expect(r.typed == ["type:a"])                         // step 2's actions never executed
    #expect(r.input.calls.contains("releaseAll"))
    #expect(r.overlay.statuses.last == "stopped (1 step)")
    #expect(!r.pipeline.isTaskActive)
}

@MainActor @Test func aRewriteHoldsTheTaskSlotAndAStopCancelsItBeforeAnythingIsTyped() async {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nohands-log-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let log = CommandLogStore(url: url)
    let hello = FocusedText(value: "Hello there.", selection: TextSpan(location: 12, length: 0), line: nil, rangeSettable: true)
    // (spoken stop during the wait?, status the row ends on, typed, what the command log says)
    let table: [(Bool, String, [String], CommandLogEntry.Outcome, String)] = [
        (false, "Hi.", ["type:Hi."], .done, "rewrote 12 → 3 characters"),
        (true, "stopped", [], .stopped, "rewrite shorter"),
    ]
    for (stop, status, typed, outcome, action) in table {
        let r = rig(commandLog: log)
        r.ax.fieldFocused = true; r.ax.field = hello
        let entered = Gate()
        r.executor.rewriter = FakeRewriter(.success("Hi.")) {
            entered.open()
            for _ in 0..<300 where stop && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
        await r.pipeline.handle(transcript: "make that shorter", trace: trace())
        #expect(r.pipeline.isTaskActive, "\(action)")                  // the wait holds the task slot, not the consumer
        await entered.wait()
        if stop { await r.pipeline.handle(transcript: "stop", trace: trace()) }
        await r.pipeline.waitForTask()
        #expect(r.typed == typed && r.overlay.statuses.last == status, "\(action)")
        // Counts only: neither the text nor the answer is in the command log.
        let entry = log.log.entries.first
        #expect(entry?.outcome == outcome && entry?.steps.first?.action == action && !r.pipeline.isTaskActive, "\(action)")
    }
}

@MainActor @Test func utteranceDuringTaskIsHeldThenRun() async {
    let r = rig()
    let entered = Gate(), release = Gate()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    r.resolver?.onResolve = { _ in entered.open(); await release.wait() }
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    await entered.wait()
    await r.pipeline.handle(transcript: "scroll down", trace: trace())   // held, then replaced (newest wins)
    await r.pipeline.handle(transcript: "click", trace: trace())
    #expect(r.input.calls.isEmpty)                         // nothing runs concurrently with the task
    let held = r.overlay.reports.filter { $0.status == .held }
    #expect(held.map(\.text) == ["scroll down", "click"])
    #expect(r.overlay.reports.contains { $0.text == "scroll down" && $0.status == .dropped(PipelineText.dropped) })   // replaced: its row is closed
    #expect(PromptStatus.held.text == "held · runs after this task (say stop to cancel)")
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .done("type a"))
    #expect(r.input.calls == ["type:a", "click:10,20"])    // the task first, then only the newest held job
    #expect(r.resolver?.calls == 1)
}

@MainActor @Test func answerToAQuestionGoesToTheTask() async {
    // (attention word, what the user says while the question waits, the answer the task gets)
    let table: [(String, [String], String)] = [
        ("", ["the knicks one"], "the knicks one"),
        ("computer", ["the knicks one", "computer, the knicks one"], "the knicks one"),   // stray speech is dropped
    ]
    for (word, said, answer) in table {
        let r = rig(attentionWord: word, sleep: { d in
            if d == TaskRunner.answerTimeout { try? await Task.sleep(for: .seconds(30)) }
        })
        r.resolver?.scripted = [step("Which game?", .ask), step("type a", .done, [.typeText("a")])]
        await r.pipeline.handle(transcript: (word.isEmpty ? "" : "computer, ") + "play the newest video", trace: trace())
        for _ in 0..<400 where r.runner?.awaitedAnswer != .question { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(r.runner?.awaitedAnswer == .question, "the question never waited")
        for words in said {
            await r.pipeline.handle(transcript: words, trace: trace())
            if words != said.last { #expect(r.runner?.awaitedAnswer == .question, "\(words) ended the question") }
        }
        await r.pipeline.waitForTask()
        #expect(r.overlay.reports.allSatisfy { $0.status != .held }, "the answer was held")
        #expect(r.resolver?.requests.dropFirst().first?.history.first?.userAnswer == answer)
        #expect(r.pipeline.lastTaskOutcome == .done("type a"))
    }
}

@MainActor @Test func dictationTypedByAFailedEditIsNotLoggedAsACommand() async {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("nohands-log-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }
    let log = CommandLogStore(url: url)
    let r = rig(commandLog: log)
    r.ax.fieldFocused = true
    r.ax.field = FocusedText(value: "Meeting at noon.", selection: TextSpan(location: 16, length: 0), line: nil, rangeSettable: true)
    await r.pipeline.handle(transcript: "start dictating", trace: trace())
    let before = log.log.entries.count
    // (spoken, in the text, so it ran as an edit)
    for (spoken, found) in [("delete the old files", false), ("delete noon", true)] {
        let n = log.log.entries.count
        await r.pipeline.handle(transcript: spoken, trace: trace())
        #expect(log.log.entries.count == n + (found ? 1 : 0), "\(spoken)")
    }
    #expect(r.typed.count == 1 && log.log.entries.count == before + 1)
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
    #expect(!r.overlay.statuses.contains { $0.hasPrefix("stopped") })
}

@MainActor @Test func pauseCancelsActiveTaskAndDropsHeldJob() async {
    let r = rig()
    let entered = Gate()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    r.resolver?.onResolve = { _ in entered.open(); await Gate().wait() }   // blocks until cancelled
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
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
}

@MainActor @Test func idleStopPhraseIsIgnored() async {
    let r = rig()
    for phrase in ["stop", "never mind", "halt"] {
        await r.pipeline.handle(transcript: phrase, trace: trace())
        #expect(!r.pipeline.isTaskActive)
    }
    #expect(r.resolver?.calls == 0)
    #expect(r.overlay.reports.isEmpty && r.overlay.huds.isEmpty)
    #expect(r.input.calls == ["releaseAll", "releaseAll", "releaseAll"])   // each stop lets go of a held button, nothing else
}

@MainActor @Test func jobHeldAfterStopNeverReplaysInNextTask() async {
    let r = rig()
    let entered = Gate(), release = Gate()
    r.resolver?.scripted = [step("type a", .continue, [.typeText("a")]), step("type b", .done, [.typeText("b")]),
                            step("type c", .done, [.typeText("c")])]
    // Step 2 blocks in a detached task, so cancelling the runner does not unblock it: the task is still unwinding.
    r.resolver?.onResolve = { n in if n == 2 { entered.open(); await Task.detached { await release.wait() }.value } }
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    await entered.wait()
    await r.pipeline.handle(transcript: "stop", trace: trace())
    await r.pipeline.handle(transcript: "click", trace: trace())   // held while the stopped task unwinds
    #expect(r.pipeline.isTaskActive)
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped)
    await r.pipeline.handle(transcript: "play the next video", trace: trace())
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .done("type c"))
    #expect(r.typed == ["type:a", "type:c"])
    #expect(!r.input.calls.contains { $0.hasPrefix("click") })    // the held click never ran
    #expect(r.overlay.reports.contains { $0.text == "click" && $0.status == .dropped(PipelineText.dropped) })
}

@MainActor @Test func heldJobOlderThan60sIsSkipped() async {
    for (age, runs) in [(Duration.seconds(30), true), (.seconds(61), false)] {
        let r = rig()
        let entered = Gate(), release = Gate()
        r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
        r.resolver?.onResolve = { _ in entered.open(); await release.wait() }
        await r.pipeline.handle(transcript: "play the newest video", trace: trace())
        await entered.wait()
        await r.pipeline.handle(transcript: "click", trace: trace(age: age))   // held regardless of age
        release.open()
        await r.pipeline.waitForTask()
        #expect(r.input.calls.contains("click:10,20") == runs)
        #expect(r.overlay.reports.contains { $0.text == "click" && $0.status == .dropped(PipelineText.dropped) } == !runs)
        #expect(!r.overlay.statuses.contains(PipelineText.skippedBusy))
    }
}

@MainActor @Test func stopDropsHeldJobAndSaysSo() async {
    let r = rig()
    let entered = Gate()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    r.resolver?.onResolve = { _ in entered.open(); await Gate().wait() }   // blocks until cancelled
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    await entered.wait()
    await r.pipeline.handle(transcript: "scroll down", trace: trace())   // held
    await r.pipeline.handle(transcript: "stop", trace: trace())
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped)
    #expect(!r.input.calls.contains("scroll"))
    // shown as stopped (not dropped) so the corner panel stays clear after a stop
    #expect(r.overlay.reports.contains { $0.text == "scroll down" && $0.status == .stopped(PipelineText.dropped) })
    #expect(!r.overlay.reports.contains { $0.text == "scroll down" && $0.status == .dropped(PipelineText.dropped) })
}

@MainActor @Test func stopRightAfterHandleCancelsBeforeTheFirstResolve() async {
    let r = rig()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    await r.pipeline.handle(transcript: "stop", trace: trace())          // the runner has not resolved yet
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped)
    #expect(r.resolver?.calls == 0)
    #expect(r.typed.isEmpty)
    #expect(r.input.calls.allSatisfy { $0 == "releaseAll" })
}

/// Feeds transcripts through a MergeBuffer built like the pipeline's (same `isComplete`) into `handle`, in order.
@MainActor private final class MergeFeed {
    let merge: MergeBuffer
    let cont: AsyncStream<String>.Continuation
    let consumer: Task<Void, Never>
    init(_ pipeline: VoicePipeline, windowMs: Int = 40, unfinishedMs: Int = 3000, attention: AttentionGate = .off) {
        let (stream, cont) = AsyncStream<String>.makeStream(bufferingPolicy: .unbounded)
        let grammar = CommandGrammar(config: AppConfig().grammarConfig)
        merge = MergeBuffer(merger: UtteranceMerger(windowMs: windowMs, unfinishedWindowMs: unfinishedMs), gate: attention,
                            isComplete: { VoicePipeline.isComplete($0, mode: $1, grammar: grammar, attention: attention) },
                            onHold: { _ in }, emit: { text, _ in cont.yield(text) })
        self.cont = cont
        consumer = Task { @MainActor in
            for await text in stream { await pipeline.handle(transcript: text, trace: trace()) }
        }
    }
    func say(_ text: String) async { await merge.transcript(text, trace: trace()) }
    /// Waits until everything emitted so far was handled.
    func drain() async { cont.finish(); await consumer.value }
}

@MainActor @Test func spokenStopThroughMergeBufferCancelsTask() async {
    // The last two rows have the attention word on: a stop works addressed and bare, and never merges into pending text.
    for (word, stop) in [("", "stop"), ("", "Stop, stop!"), ("", "no stop"), ("computer", "computer, stop"), ("computer", "um computer cancel that"), ("computer", "stop")] {
        let r = rig(attentionWord: word)
        let entered = Gate(), release = Gate()
        r.resolver?.scripted = [step("type a", .continue, [.typeText("a")]), step("type b", .done, [.typeText("b")])]
        r.resolver?.onResolve = { n in if n == 2 { entered.open(); await release.wait() } }
        let feed = MergeFeed(r.pipeline, attention: AttentionGate(configured: word))
        await feed.say(word.isEmpty ? "play the newest video" : "computer play the newest video")   // not a grammar command: released after the short window
        await entered.wait()                               // the task is resolving step 2
        await feed.say(word.isEmpty ? "open the" : "computer open the")   // dangling: would wait 3 s and merge with what follows
        await feed.say(stop)                               // must not become "open the stop"
        await feed.drain()
        release.open()
        await r.pipeline.waitForTask()
        #expect(r.pipeline.lastTaskOutcome == .stopped, "\(stop)")
        #expect(r.typed == ["type:a"])
        #expect(!r.overlay.statuses.contains(PromptStatus.held.text))   // the stop was never held or merged
        #expect(r.overlay.statuses.last == "stopped (1 step)")
    }
}

@MainActor @Test func straySpeechDuringTaskNeverReplacesAHeldCommand() async {
    let r = rig(attentionWord: "computer")
    let entered = Gate(), release = Gate()
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    r.resolver?.onResolve = { _ in entered.open(); await release.wait() }
    await r.pipeline.handle(transcript: "computer play the newest video", trace: trace())
    await entered.wait()
    await r.pipeline.handle(transcript: "computer click", trace: trace())   // held
    await r.pipeline.handle(transcript: "new tab", trace: trace())          // stray: dropped silently
    await r.pipeline.handle(transcript: "Computer.", trace: trace())        // the word alone: dropped too
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.input.calls == ["type:a", "click:10,20"])                     // the held command still ran
    #expect(!r.overlay.reports.contains { $0.text == "computer click" && $0.status == .dropped(PipelineText.dropped) })
}

// MARK: - switching backend live

@MainActor private func newRunner(_ r: Rig, _ resolver: FakeResolver) -> TaskRunner {
    TaskRunner(config: AppConfig(), resolver: resolver, executor: r.executor, observer: r.observer, overlay: r.overlay, sleep: { _ in })
}

@MainActor @Test func switchedRunnerTakesTheNextCommandAndNeverTheRunningTask() async throws {
    let typeA = step("type a", .done, [.typeText("a")]), typeB = step("type b", .done, [.typeText("b")])
    // Idle, or no runner at launch: the next command goes to the new runner.
    for withResolver in [true, false] {
        let r = rig(withResolver: withResolver)
        let b = FakeResolver()
        b.scripted = [typeB]
        r.pipeline.replaceRunner(newRunner(r, b))
        await r.pipeline.handle(transcript: "make it bigger", trace: trace())
        await r.pipeline.waitForTask()
        #expect(r.typed == ["type:b"] && r.resolver?.calls ?? 0 == 0, "idle, had runner: \(withResolver)")
    }
    // During a task: it stays on its runner; a spoken stop still cancels that runner; a held command goes to the new one.
    for stop in [true, false] {
        let r = rig()
        let a = try #require(r.resolver), b = FakeResolver()
        let entered = Gate(), release = Gate()
        a.scripted = [typeA]
        b.scripted = [typeB]
        a.onResolve = { _ in entered.open(); await release.wait() }
        await r.pipeline.handle(transcript: "play the newest video", trace: trace())
        await entered.wait()
        let replacement = newRunner(r, b)
        r.pipeline.replaceRunner(replacement)
        await r.pipeline.handle(transcript: stop ? "stop" : "make it bigger", trace: trace())
        release.open()
        await r.pipeline.waitForTask()
        #expect(b.calls == (stop ? 0 : 1) && a.calls == 1, "stop: \(stop)")
        #expect(!replacement.cancelled, "stop: \(stop): the stop must reach the running runner, not the waiting one")
        #expect(r.pipeline.lastTaskOutcome == (stop ? .stopped : .done("type b")), "stop: \(stop)")
        #expect(r.typed == (stop ? [] : ["type:a", "type:b"]), "stop: \(stop)")
        // The swap still lands once the task is over.
        await r.pipeline.handle(transcript: "make it smaller", trace: trace())
        await r.pipeline.waitForTask()
        #expect(b.calls == (stop ? 1 : 2) && a.calls == 1, "after, stop: \(stop)")
    }
}

private let nightGame = #"{"night game":["click","play the newest video","scroll down"]}"#

@MainActor @Test func macroRunsItsStepsInOrderOnOneRow() async {
    let r = rig(macros: nightGame)
    r.resolver?.scripted = [step("type a", .done, [.typeText("a")])]
    await r.pipeline.handle(transcript: "Night game.", trace: trace())
    await r.pipeline.waitForTask()
    #expect(r.input.calls.filter { $0 != "releaseAll" } == ["click:10,20", "type:a", "scroll"])
    #expect(Set(r.overlay.reports.map(\.id)).count == 1)
    #expect(r.overlay.statuses.contains("step 2 of 3 · play the newest video"))
    #expect(r.overlay.statuses.contains("step 2 of 3 · step 1 · type a"))   // the runner's line, relabelled
    #expect(r.overlay.statuses.last == "done · 3 steps")
}

@MainActor @Test func stopPhraseEndsAMacroAtItsStep() async {
    let r = rig(macros: nightGame)
    let entered = Gate(), release = Gate()
    r.resolver?.onResolve = { _ in entered.open(); await release.wait() }
    await r.pipeline.handle(transcript: "night game", trace: trace())
    await entered.wait()                                   // step 2 is resolving
    await r.pipeline.handle(transcript: "stop", trace: trace())
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.input.calls.filter { $0 != "releaseAll" } == ["click:10,20"])   // step 3 never ran
    #expect(r.overlay.reports.first { $0.id == 1 && $0.status == .stopped("stopped at step 2 of 3") } != nil)
    #expect(!r.pipeline.isTaskActive)
}

@MainActor @Test func aFailingStepEndsTheMacroAndNamesTheStep() async {
    // (resolver, what the row ends on)
    let table: [(Result<[Action], IntentError>?, String)] = [
        (.failure(.timeout), "step 2 of 3 · timed out"),
        (nil, "step 2 of 3 · \(PipelineText.llmOff)"),         // LLM off: the grammar step still ran
    ]
    for (result, last) in table {
        let r = rig(withResolver: result != nil, macros: nightGame)
        if let result { r.resolver?.result = result }
        await r.pipeline.handle(transcript: "night game", trace: trace())
        await r.pipeline.waitForTask()
        #expect(r.overlay.statuses.last == last)
        #expect(r.input.calls.filter { $0 != "releaseAll" } == ["click:10,20"], "\(last)")
        #expect(r.overlay.reports.last?.status == .failed(last))
    }
}

@MainActor @Test func forgetPhrasesDropTheLastRoutesOrAllOfThem() async {
    let click = Action.click(.cursor, button: .left, count: 1)
    let past = Route(goal: "other goal", host: nil, steps: [RouteStep(intent: "x", actions: ["click"])], savedAt: .distantPast)
    // (phrase, the row it ends on, routes left of the other one and this task's)
    let table: [(String, String, Int)] = [
        ("forget that route", "forgot that route", 1), ("forget all routes", "forgot all routes", 0),
        ("night game", "done · 1 step", 0),   // a macro step saying "forget all routes" does what the spoken phrase does
    ]
    for (phrase, row, left) in table {
        let store = FakeRouteStore()
        store.routes = [past]
        let r = rig(macros: #"{"night game":["forget all routes"]}"#, routes: store)
        r.resolver?.scripted = [step("a", .continue, [click]), step("b", .done, [click])]
        await r.pipeline.handle(transcript: "tidy up the desk", trace: trace())
        await r.pipeline.waitForTask()
        #expect(store.routes.count == 2, "\(phrase)")   // the other route and this task's
        await r.pipeline.handle(transcript: phrase, trace: trace())
        await r.pipeline.waitForTask()
        #expect(r.overlay.reports.last?.status.text.hasPrefix(row) == true, "\(phrase): \(r.overlay.reports.last?.status.text ?? "")")
        #expect(store.routes.count == left, "\(phrase)")
        if phrase == "forget that route" {
            await r.pipeline.handle(transcript: phrase, trace: trace())   // nothing left to drop
            #expect(r.overlay.reports.last?.status.text == "no route to forget")
        }
    }
}

// MARK: - Spoken feedback (NH-60)

@MainActor private final class FakeSpeaker: FeedbackSpeaking {
    var said: [String] = []
    var cuts = 0
    var current: SpokenLine?
    func speak(_ text: String) { said.append(text); current = SpokenLine(text: text, start: .now) }
    func cut() { cuts += 1; if current?.end == nil { current?.end = .now } }
}

/// A rig whose pipeline speaks at `level` through a fake speaker, built only when a line is first said.
@MainActor private func talking(_ level: SpeakLevel, attentionWord: String = "",
                                sleep: @escaping @Sendable (Duration) async -> Void = { _ in }) -> (Rig, FakeSpeaker, built: () -> Int) {
    let r = rig(attentionWord: attentionWord, sleep: sleep), fake = FakeSpeaker()
    var built = 0
    r.pipeline.speakerFactory = { built += 1; return fake }
    r.pipeline.setSpeakLevel(level)
    return (r, fake, { built })
}

@MainActor @Test func aTasksFinishLineIsSpokenOnceAtTheLevelAndNeverWhenOffOrAway() async {
    // (level, what the task ends as, what the model does last, what is said)
    let table: [(SpeakLevel, IntentError?, [Action], [String])] = [
        (.off, nil, [], []),
        (.outcomes, nil, [], ["Done: open the menu."]),
        (.outcomes, .timeout, [], ["Timed out."]),
        (.outcomes, nil, [.setMode(.dictation)], []),   // the words would be typed
        (.all, nil, [.setMode(.sleep)], []),
    ]
    for (level, failure, actions, said) in table {
        let (r, fake, built) = talking(level)
        if let failure { r.resolver?.result = .failure(failure) } else { r.resolver?.scripted = [step("open the menu", .done, actions)] }
        await r.pipeline.handle(transcript: "play the newest video", trace: trace())
        await r.pipeline.waitForTask()
        #expect(fake.said == said, "\(level) \(actions)")
        if level == .off { #expect(built() == 0) }   // nothing is created while off
    }
}

@MainActor @Test func aStopPhraseCutsTheSpeechEvenIfItEchoesAndStillCancelsTheTask() async {
    let (r, fake, _) = talking(.outcomes)
    await r.pipeline.handle(transcript: "spoken feedback on", trace: trace())   // a line is playing (and the speaker exists)
    fake.current = SpokenLine(text: "stop", start: .now.advanced(by: .seconds(-1)))   // and it holds the word
    let entered = Gate(), release = Gate()
    r.resolver?.scripted = [step("type a", .continue, [.typeText("a")]), step("type b", .done, [.typeText("b")])]
    r.resolver?.onResolve = { n in if n == 2 { entered.open(); await release.wait() } }
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    await entered.wait()
    let before = fake.cuts
    await r.pipeline.handle(transcript: "stop", trace: trace())
    #expect(fake.cuts == before + 1)   // cut, not dropped as an echo of its own word
    release.open()
    await r.pipeline.waitForTask()
    #expect(r.pipeline.lastTaskOutcome == .stopped && r.typed == ["type:a"])
    #expect(fake.said == ["Spoken feedback on."])   // a stopped task says nothing more
}

@MainActor @Test func aQuestionIsSpokenAtAllAndItsEchoIsNeverTheAnswer() async {
    let (r, fake, _) = talking(.all, sleep: { d in if d == TaskRunner.answerTimeout { try? await Task.sleep(for: .seconds(30)) } })
    r.resolver?.scripted = [step("Which game?", .ask), step("type a", .done, [.typeText("a")])]
    await r.pipeline.handle(transcript: "play the newest video", trace: trace())
    for _ in 0..<400 where r.runner?.awaitedAnswer != .question { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(fake.said == ["Which game?"])
    let cuts = fake.cuts
    await r.pipeline.handle(transcript: "which game", trace: trace())   // its own voice, heard back
    #expect(r.runner?.awaitedAnswer == .question && fake.cuts == cuts)
    await r.pipeline.handle(transcript: "the knicks one", trace: trace())   // the user: cuts the speech and answers
    await r.pipeline.waitForTask()
    #expect(fake.cuts > cuts)
    #expect(r.resolver?.requests.dropFirst().first?.history.first?.userAnswer == "the knicks one")
}

@MainActor @Test func aLineHeardBackAtItsEndIsMeasuredFromTheVoiceNotTheVadsSilenceWait() async {
    // The line ended 1.5 s ago and its echo stopped 0.2 s after that; the VAD closes the utterance only now.
    // (voiceEnd, speechEnd, dropped as the line's own voice)
    let table: [(Duration?, Duration, Bool)] = [(.seconds(-1.3), .zero, true), (nil, .zero, false)]
    for (voiceEnd, speechEnd, dropped) in table {
        let (r, fake, _) = talking(.all, sleep: { d in if d == TaskRunner.answerTimeout { try? await Task.sleep(for: .seconds(30)) } })
        r.resolver?.scripted = [step("Which game?", .ask), step("type a", .done, [.typeText("a")])]
        await r.pipeline.handle(transcript: "play the newest video", trace: trace())
        for _ in 0..<400 where r.runner?.awaitedAnswer != .question { try? await Task.sleep(for: .milliseconds(5)) }
        fake.current = SpokenLine(text: "Which game?", start: .now.advanced(by: .seconds(-4)), end: .now.advanced(by: .seconds(-1.5)))
        let cuts = fake.cuts
        var t = trace()
        t.speechEnd = .now.advanced(by: speechEnd)
        t.voiceEnd = voiceEnd.map { .now.advanced(by: $0) }
        await r.pipeline.handle(transcript: "which game", trace: t)
        #expect((fake.cuts == cuts) == dropped, "voiceEnd \(String(describing: voiceEnd))")
        await r.pipeline.handle(transcript: "the knicks one", trace: trace())
        await r.pipeline.waitForTask()
    }
}

@MainActor @Test func theVoicePhrasesChangeTheLevelAtOnce() async {
    // (phrase, level after, what is said)
    let table: [(String, SpeakLevel, [String])] = [
        ("spoken feedback on", .outcomes, ["Spoken feedback on."]), ("spoken feedback all", .all, ["Spoken feedback all."]),
        ("turn off spoken feedback", .off, []),
    ]
    for (phrase, level, said) in table {
        let (r, fake, _) = talking(.outcomes)
        var heard: [SpeakLevel] = []
        r.pipeline.onSpeakLevelChange = { heard.append($0) }
        await r.pipeline.handle(transcript: phrase, trace: trace())
        #expect(r.pipeline.speakLevel == level && heard == [level] && fake.said == said, "\(phrase)")
    }
}
