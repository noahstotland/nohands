import Testing
import CoreGraphics
import Foundation
import NoHandsCore
@testable import NoHandsMac

/// Returns scripted steps in order (the last one repeats) and records every request.
private final class FakeResolver: IntentResolving, @unchecked Sendable {
    var steps: [Result<IntentStep, IntentError>]
    var requests: [StepRequest] = []
    /// Called with the 1-based call number before the step is returned.
    var onResolve: (@Sendable (Int) async -> Void)?
    init(_ steps: [IntentStep]) { self.steps = steps.map { .success($0) } }
    init(results: [Result<IntentStep, IntentError>]) { self.steps = results }
    func resolve(_ request: StepRequest) async throws -> IntentStep {
        requests.append(request)
        let n = requests.count
        await onResolve?(n)
        return try steps[min(n - 1, steps.count - 1)].get()
    }
}

private func el(_ id: Int, _ title: String, x: CGFloat = 100) -> UIElementInfo {
    UIElementInfo(id: id, frame: CGRect(x: x, y: CGFloat(id) * 40, width: 80, height: 30), title: title, role: "AXButton")
}

@MainActor private struct Rig {
    var runner: TaskRunner
    var resolver: FakeResolver
    var input: FakeInput
    var ax: FakeElements
    var overlay: FakeOverlay
    var typed: [String] { input.calls.filter { $0.hasPrefix("type:") } }
    var releaseAllCalls: Int { input.calls.filter { $0 == "releaseAll" }.count }
}

@MainActor private func rig(_ resolver: FakeResolver, maxSteps: Int = 12, settleMs: Int = 3000) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    ax.front = "Safari"
    ax.elements = [el(1, "Reload")]
    var config = AppConfig()
    config.maxTaskSteps = maxSteps
    config.settleMs = settleMs
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config, frontTimeout: .milliseconds(100))
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: config.maxObservedElements),
                            overlay: overlay, sleep: { _ in })
    return Rig(runner: runner, resolver: resolver, input: input, ax: ax, overlay: overlay)
}

private func step(_ intent: String, _ status: StepStatus, _ actions: [Action] = []) -> IntentStep {
    IntentStep(intent: intent, status: status, actions: actions)
}

@MainActor @Test func doneOnFirstStepIsOneCall() async {
    let r = rig(FakeResolver([step("type hi", .done, [.typeText("hi")])]))
    let outcome = await r.runner.run(goal: "type hi", mode: .command)
    #expect(outcome == .done("type hi"))
    #expect(r.resolver.requests.count == 1)
    #expect(r.typed == ["type:hi"])
    let req = r.resolver.requests[0]
    #expect(req.goal == "type hi" && req.step == 1 && req.maxSteps == 12 && req.history.isEmpty)
    #expect(req.observation.app == "Safari")
    #expect(req.observation.elements.map(\.title) == ["Reload"])
    #expect(r.overlay.huds == ["step 1 · type hi", "done · type hi"])
    #expect(r.releaseAllCalls == 0)
}

@MainActor @Test func doneWithEmptyIntentShowsPlainDone() async {
    let r = rig(FakeResolver([step("", .done)]))
    #expect(await r.runner.run(goal: "x", mode: .command) == .done(""))
    #expect(r.overlay.huds.last == "done")
}

@MainActor @Test func continueThenDoneObservesTwiceAndCarriesHistory() async {
    let resolver = FakeResolver([step("open search", .continue, [.typeText("a")]),
                                 step("finished", .done)])
    let r = rig(resolver)
    let ax = r.ax
    resolver.onResolve = { n in if n == 1 { ax.elements = [el(1, "Reload"), el(2, "Search", x: 300)] } }
    let outcome = await r.runner.run(goal: "search", mode: .command)
    #expect(outcome == .done("finished"))
    #expect(resolver.requests.count == 2)
    let second = resolver.requests[1]
    #expect(second.step == 2)
    #expect(second.history == [StepRecord(intent: "open search", actions: [.typeText("a")], failure: nil)])
    #expect(second.observation.elements.map(\.title) == ["Reload", "Search"])
    #expect(r.overlay.huds == ["step 1 · open search", "step 2 · finished", "done · finished"])
}

@MainActor @Test func labelsOfObservedScreenAreUsedForExecution() async {
    let r = rig(FakeResolver([step("click reload", .done, [.click(.label(1), button: .left, count: 1)])]))
    #expect(await r.runner.run(goal: "reload", mode: .command) == .done("click reload"))
    #expect(r.input.calls == ["click:140,55"])
}

@MainActor @Test func failedActionIsReportedInHistoryAndLoopContinues() async {
    let resolver = FakeResolver([step("open it", .continue, [.openApp("Nope")]),
                                 step("gave up", .stuck)])
    let r = rig(resolver)
    let outcome = await r.runner.run(goal: "open nope", mode: .command)
    #expect(outcome == .stuck("gave up"))
    #expect(resolver.requests.count == 2)
    #expect(resolver.requests[1].history == [StepRecord(intent: "open it", actions: [.openApp("Nope")],
                                                        failure: "no app named Nope")])
    #expect(r.overlay.huds.last == "stuck: gave up")
}

@MainActor @Test func stepCapEndsAsStuck() async {
    var n = 0
    let resolver = FakeResolver((1...5).map { _ in n += 1; return step("scroll \(n)", .continue, [.scroll(.down, amount: n)]) })
    let r = rig(resolver, maxSteps: 3)
    let outcome = await r.runner.run(goal: "scroll forever", mode: .command)
    #expect(outcome == .stuck("step limit reached"))
    #expect(resolver.requests.count == 3)
    #expect(resolver.requests.map(\.step) == [1, 2, 3])
    #expect(resolver.requests.allSatisfy { $0.maxSteps == 3 })
    #expect(r.overlay.huds.last == "stuck: step limit reached")
}

@MainActor @Test func threeIdenticalStepsEndAsStuck() async {
    let resolver = FakeResolver([step("scroll", .continue, [.scroll(.down, amount: 5)])])
    let r = rig(resolver)
    let outcome = await r.runner.run(goal: "scroll", mode: .command)
    #expect(outcome == .stuck("repeating the same action"))
    #expect(resolver.requests.count == 3)
    #expect(r.input.calls.filter { $0 == "scroll" }.count == 2)   // the third repeat is not executed
    #expect(r.releaseAllCalls == 1)
}

@MainActor @Test func cancelBeforeSecondExecuteStopsAndReleases() async {
    let resolver = FakeResolver([step("one", .continue, [.typeText("1")]),
                                 step("two", .continue, [.typeText("2")])])
    let r = rig(resolver)
    let runner = r.runner
    resolver.onResolve = { n in if n == 2 { await runner.cancel() } }
    let outcome = await runner.run(goal: "count", mode: .command)
    #expect(outcome == .stopped)
    #expect(r.typed == ["type:1"])
    #expect(resolver.requests.count == 2)
    #expect(r.releaseAllCalls == 1)
    #expect(r.overlay.huds.last == "stopped")
}

@MainActor @Test func cancelInterruptsWaitAction() async {
    let resolver = FakeResolver([step("wait then type", .continue, [.wait(ms: 5000), .typeText("late")])])
    let r = rig(resolver)
    let runner = r.runner
    let task = Task { await runner.run(goal: "slow", mode: .command) }
    try? await Task.sleep(for: .milliseconds(100))
    runner.cancel()
    let start = ContinuousClock.now
    let outcome = await task.value
    #expect(outcome == .stopped)
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(r.typed.isEmpty)
}

@MainActor @Test func resolverCancelledErrorIsStopped() async {
    let r = rig(FakeResolver(results: [.failure(.cancelled)]))
    #expect(await r.runner.run(goal: "x", mode: .command) == .stopped)
    #expect(r.releaseAllCalls == 1)
}

@MainActor @Test func resolverErrorIsFailedWithHUDText() async {
    let r = rig(FakeResolver(results: [.failure(.timeout)]))
    #expect(await r.runner.run(goal: "x", mode: .command) == .failed("timed out"))
    #expect(r.overlay.huds.last == "timed out")
    #expect(r.releaseAllCalls == 1)
}

@MainActor @Test func ignoreRunsNothing() async {
    let r = rig(FakeResolver([step("chatter", .ignore, [.typeText("no")])]))
    #expect(await r.runner.run(goal: "hello there", mode: .command) == .ignored)
    #expect(r.input.calls == ["releaseAll"])
    #expect(r.overlay.huds == [PipelineText.didntCatch])
}

@MainActor @Test func stuckRunsNothing() async {
    let r = rig(FakeResolver([step("no such button", .stuck, [.typeText("no")])]))
    #expect(await r.runner.run(goal: "press it", mode: .command) == .stuck("no such button"))
    #expect(r.input.calls == ["releaseAll"])
    #expect(r.overlay.huds == ["stuck: no such button"])
}

@MainActor @Test func settleZeroObservesOnceAndStillRuns() async {
    let r = rig(FakeResolver([step("a", .continue, [.typeText("a")]), step("b", .done)]), settleMs: 0)
    #expect(await r.runner.run(goal: "x", mode: .command) == .done("b"))
}

@MainActor @Test func settleWaitsForTwoEqualObservations() async {
    let ax = FakeElements()
    ax.front = "Chrome"
    let counter = SleepCounter()
    var config = AppConfig(); config.settleMs = 3000
    let overlay = FakeOverlay()
    let executor = ActionExecutor(input: FakeInput(), ax: ax, overlay: overlay, config: config)
    let runner = TaskRunner(config: config, resolver: FakeResolver([step("", .done)]), executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120), overlay: overlay,
                            sleep: { _ in await counter.tick { n in if n == 1 { ax.elements = [el(1, "Page")] } } })
    let (obs, _) = await runner.settle(mode: .command)
    // obs0 empty, sleep1 -> page appears, obs1 differs; sleep2 obs2 same but 500ms ≥ 300ms → stop.
    #expect(obs.elements.map(\.title) == ["Page"])
    #expect(await counter.count == 2)
}

@MainActor @Test func settleStopsAtMax() async {
    let ax = FakeElements()
    let counter = SleepCounter()
    var config = AppConfig(); config.settleMs = 1000
    let overlay = FakeOverlay()
    let executor = ActionExecutor(input: FakeInput(), ax: ax, overlay: overlay, config: config)
    let runner = TaskRunner(config: config, resolver: FakeResolver([step("", .done)]), executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120), overlay: overlay,
                            sleep: { _ in await counter.tick { n in ax.elements = [el(1, "t\(n)")] } })
    _ = await runner.settle(mode: .command)
    #expect(await counter.count == 4)   // 4 × 250 ms = settleMs
}

private actor SleepCounter {
    var count = 0
    func tick(_ body: @Sendable (Int) -> Void) { count += 1; body(count) }
}

@MainActor @Test func cancellingTheCallingTaskStops() async {
    let resolver = FakeResolver([step("wait", .continue, [.wait(ms: 5000), .typeText("late")])])
    let r = rig(resolver)
    let runner = r.runner
    let task = Task { await runner.run(goal: "slow", mode: .command) }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    #expect(await task.value == .stopped)
    #expect(r.typed.isEmpty)
    #expect(r.releaseAllCalls == 1)
}

@MainActor @Test func doneWithFailedActionsContinuesWithFailureInHistory() async {
    let resolver = FakeResolver([step("open it", .done, [.openApp("Nope")]),
                                 step("opened", .done)])
    let r = rig(resolver)
    #expect(await r.runner.run(goal: "open nope", mode: .command) == .done("opened"))
    #expect(resolver.requests.count == 2)
    #expect(resolver.requests[1].history == [StepRecord(intent: "open it", actions: [.openApp("Nope")],
                                                        failure: "no app named Nope")])
    #expect(r.releaseAllCalls == 0)
}

@MainActor @Test func repeatedFailingDoneEndsAsStuck() async {
    let resolver = FakeResolver([step("open it", .done, [.openApp("Nope")])])
    let r = rig(resolver)
    #expect(await r.runner.run(goal: "open nope", mode: .command) == .stuck("repeating the same action"))
    #expect(resolver.requests.count == 3)
    #expect(resolver.requests[2].history.count == 2)
    #expect(r.releaseAllCalls == 1)
    #expect(r.overlay.huds.last == "stuck: repeating the same action")
}

@MainActor @Test func onStepReportsEachExecutedStepWithFailure() async {
    let r = rig(FakeResolver([step("open it", .continue, [.openApp("Nope")]),
                              step("type hi", .done, [.typeText("hi")])]))
    var seen: [String] = []
    r.runner.onStep = { n, s, settle, failure in
        #expect(settle >= .zero)
        seen.append("\(n) \(s.intent) \(failure ?? "ok")")
    }
    #expect(await r.runner.run(goal: "x", mode: .command) == .done("type hi"))
    #expect(seen == ["1 open it no app named Nope", "2 type hi ok"])
}

@MainActor @Test func blockedShortcutRunsNothingAndRecordsFailure() async {
    let resolver = FakeResolver([step("go to the url", .continue, [.pressKey(KeyChord(.w, [.command])), .typeText("youtube.com")]),
                                 step("gave up", .stuck)])
    let r = rig(resolver)
    #expect(await r.runner.run(goal: "open the latest video", mode: .command) == .stuck("gave up"))
    #expect(r.input.calls.allSatisfy { $0 == "releaseAll" })   // nothing typed or pressed
    #expect(resolver.requests[1].history == [StepRecord(
        intent: "go to the url", actions: [.pressKey(KeyChord(.w, [.command])), .typeText("youtube.com")],
        failure: "blocked: command-w not allowed for this request")])
}

// MARK: - first observation, badge numbers, mid-task ignore, exit status

@MainActor private func countingRunner(_ resolver: FakeResolver, ax: FakeElements, overlay: FakeOverlay = FakeOverlay(),
                                       sleeps: SleepCounter, clock: FakeClock = FakeClock()) -> TaskRunner {
    var config = AppConfig(); config.settleMs = 3000
    let executor = ActionExecutor(input: FakeInput(), ax: ax, overlay: overlay, config: config)
    return TaskRunner(config: config, resolver: resolver, executor: executor,
                      observer: ScreenObserver(ax: ax, maxElements: 120), overlay: overlay,
                      sleep: { _ in await sleeps.tick { _ in } }, now: { clock.now() })   // walks take no time
}

@MainActor @Test func firstStepObservesOnceWhenNothingWasJustExposed() async {
    let ax = FakeElements(); ax.elements = [el(1, "Reload")]
    let sleeps = SleepCounter()
    let resolver = FakeResolver([step("", .done)])
    let walksAtResolve = WalkLog()
    resolver.onResolve = { _ in await walksAtResolve.set(ax.walks) }
    let runner = countingRunner(resolver, ax: ax, sleeps: sleeps)
    #expect(await runner.run(goal: "x", mode: .command) == .done(""))
    #expect(await walksAtResolve.value == 1)
    #expect(await sleeps.count == 0)
}

@MainActor @Test func firstStepSettlesWhenAChromiumTreeWasJustExposed() async {
    let ax = FakeElements(); ax.elements = [el(1, "Reload")]
    ax.exposeOnNextWalk = true
    let sleeps = SleepCounter()
    let resolver = FakeResolver([step("", .done)])
    let walksAtResolve = WalkLog()
    resolver.onResolve = { _ in await walksAtResolve.set(ax.walks) }
    let runner = countingRunner(resolver, ax: ax, sleeps: sleeps)
    #expect(await runner.run(goal: "x", mode: .command) == .done(""))
    #expect(await sleeps.count == 2)                // settled: two equal observations after ≥ 300 ms
    #expect(await walksAtResolve.value == 3)
}

private actor WalkLog {
    var value = 0
    func set(_ v: Int) { value = v }
}

@MainActor @Test func shownBadgesKeepTheirNumbersForTheModelAndTheClick() async {
    let ax = FakeElements()
    ax.elements = [el(1, "Reload"), el(2, "Save", x: 300)]       // a fresh walk would number these 1, 2
    let overlay = FakeOverlay()
    overlay.state = .labels([7: el(7, "Save", x: 300), 9: el(9, "Open", x: 500)])   // what the badges show
    let input = FakeInput()
    var config = AppConfig(); config.settleMs = 0
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config)
    let resolver = FakeResolver([step("click open", .done, [.click(.label(9), button: .left, count: 1)])])
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120), overlay: overlay, sleep: { _ in })
    #expect(await runner.run(goal: "click 9", mode: .command) == .done("click open"))
    let obs = resolver.requests[0].observation
    #expect(obs.overlay == "labels")
    #expect(obs.elements.map(\.number) == [7, 9])
    #expect(obs.elements.map(\.title) == ["Save", "Open"])
    #expect(input.calls == ["click:540,375"])                    // badge 9's frame
}

@MainActor @Test func ignoreAfterEarlierStepsShowsStoppedWithIntent() async {
    let r = rig(FakeResolver([step("type a", .continue, [.typeText("a")]), step("cannot find the button", .ignore)]))
    #expect(await r.runner.run(goal: "x", mode: .command) == .ignored)
    #expect(r.overlay.huds.last == "stopped: cannot find the button")
    #expect(r.releaseAllCalls == 1)
}

@Test func taskExitStatus() {
    #expect(TaskOutcome.done("x").exitStatus == 0)
    #expect(TaskOutcome.ignored.exitStatus == 0)
    #expect(TaskOutcome.stuck("x").exitStatus == 2)
    #expect(TaskOutcome.failed("x").exitStatus == 2)
    #expect(TaskOutcome.stopped.exitStatus == 2)
}

@MainActor @Test func settleObservesOffTheMainActorAndCountsWalkTime() async {
    let ax = FakeElements()
    let clock = FakeClock()
    ax.onWalk = { clock.advance(.milliseconds(300)) }                     // each walk "takes" 300 ms
    let counter = SleepCounter()
    var config = AppConfig(); config.settleMs = 1000
    let overlay = FakeOverlay()
    let executor = ActionExecutor(input: FakeInput(), ax: ax, overlay: overlay, config: config)
    let runner = TaskRunner(config: config, resolver: FakeResolver([step("", .done)]), executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120), overlay: overlay,
                            sleep: { _ in await counter.tick { n in ax.elements = [el(1, "t\(n)")] } },   // never settles
                            now: { clock.now() })
    _ = await runner.settle(mode: .command)
    // 300 (walk) + 250 (sleep) + 300 (walk) = 850; then a 150 ms sleep reaches 1000: 2 sleeps, not 4.
    #expect(await counter.count == 2)
    #expect(ax.walkedOnMainThread == [false, false, false])
    #expect(ax.walkScreens.allSatisfy { $0 == [CGRect(x: 0, y: 0, width: 1000, height: 800)] })   // read on main, passed in
}

@MainActor @Test func badgesAreHiddenAfterAStepSoTheNextObservationWalksAfresh() async {
    let ax = FakeElements()
    ax.elements = [el(1, "Reload")]
    let overlay = FakeOverlay()
    overlay.state = .labels([9: el(9, "Open", x: 500)])
    let input = FakeInput()
    var config = AppConfig(); config.settleMs = 0
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config)
    let resolver = FakeResolver([step("click open", .continue, [.click(.label(9), button: .left, count: 1)]),
                                 step("finished", .done)])
    resolver.onResolve = { n in if n == 1 { ax.elements = [el(1, "Reload"), el(2, "Opened page", x: 300)] } }
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120), overlay: overlay, sleep: { _ in })
    #expect(await runner.run(goal: "open it", mode: .command) == .done("finished"))
    #expect(input.calls == ["click:540,375"])                     // step 1 used badge 9
    #expect(overlay.state == .none)                               // hidden after step 1 acted
    let second = resolver.requests[1].observation
    #expect(second.overlay == "none")
    #expect(second.elements.map(\.title) == ["Reload", "Opened page"])   // a fresh walk, not the old badge map
}

@MainActor @Test func overlayDrawnByTheStepItselfStaysUp() async {
    let r = rig(FakeResolver([step("show numbers", .continue, [.showLabels]), step("finished", .done)]), settleMs: 0)
    #expect(await r.runner.run(goal: "show the numbers", mode: .command) == .done("finished"))
    if case .labels = r.overlay.state {} else { Issue.record("labels were hidden: \(r.overlay.state)") }
}

// MARK: harness

private func harnessSnapshot() -> DesktopSnapshot {
    DesktopSnapshot(app: "Safari", snapshotID: "s1", windowID: "w-1", windowTitle: "Safari", complete: true, elements: [
        UIElementInfo(id: 1, frame: CGRect(x: 0, y: 0, width: 10, height: 10), title: "Reload", role: "button", ref: "@s1:e1")])
}

@MainActor private func harnessRig(_ resolver: FakeResolver, harness: FakeHarness, trace: Bool = false) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    ax.front = "Safari"
    ax.elements = [el(1, "Reload")]
    var config = AppConfig()
    config.settleMs = 0
    config.agentDesktopTrace = trace
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config, frontTimeout: .milliseconds(100),
                                  harness: harness, clipboard: FakeClipboard())
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120, harness: harness),
                            overlay: overlay, sleep: { _ in }, harness: harness)
    return Rig(runner: runner, resolver: resolver, input: input, ax: ax, overlay: overlay)
}

@MainActor @Test func readingsFlowIntoTheNextObservation() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.readResult = "hi"
    let r = harnessRig(FakeResolver([step("read", .continue, [.readClipboard]), step("look", .continue, [.wait(ms: 100)]),
                                     step("done", .done)]), harness: h)
    #expect(await r.runner.run(goal: "what's on the clipboard", mode: .command) == .done("done"))
    #expect(r.resolver.requests.count == 3)
    #expect(r.resolver.requests[0].observation.readings.isEmpty)
    #expect(r.resolver.requests[1].observation.readings == ["clipboard: hi"])
    #expect(r.resolver.requests[2].observation.readings.isEmpty)
    #expect(r.resolver.requests.allSatisfy { $0.observation.harness == .agentDesktop && $0.observation.elements.first?.title == "Reload" })
}

@MainActor @Test func doneWithReadingsShowsTheFirstOneInTheHUD() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.readResult = "hello world"
    let r = harnessRig(FakeResolver([step("read it", .done, [.readClipboard])]), harness: h)
    #expect(await r.runner.run(goal: "read the clipboard", mode: .command) == .done("read it"))
    #expect(r.overlay.huds.last == "read it — clipboard: hello world")
}

@MainActor @Test func sessionStartsAndEndsWhenTracing() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]
    let r = harnessRig(FakeResolver([step("done", .done)]), harness: h, trace: true)
    _ = await r.runner.run(goal: "nothing", mode: .command)
    #expect(h.calls.first == "session:start" && h.calls.last == "session:end:sess-1")
    let h2 = FakeHarness(); h2.snapshotResults = [harnessSnapshot()]
    let r2 = harnessRig(FakeResolver([step("done", .done)]), harness: h2)
    _ = await r2.runner.run(goal: "nothing", mode: .command)
    #expect(!h2.calls.contains { $0.hasPrefix("session") })
}

@MainActor @Test func elementChangedFailureIsRecordedForTheModel() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.actResults = [.elementChanged]
    let r = harnessRig(FakeResolver([step("click", .continue, [.click(.label(1), button: .left, count: 1)]), step("done", .done)]), harness: h)
    _ = await r.runner.run(goal: "reload", mode: .command)
    #expect(r.resolver.requests[1].history.first?.failure == ActionExecutor.elementChanged)
    #expect(ClaudeRequestBuilder.userMessage(request: r.resolver.requests[1]).contains("FAILED: element changed, look again"))
}

@MainActor @Test func harnessKindIsFixedForTheWholeTask() async {
    // Snapshot works on step 1 but not on step 2: the task stays an agent-desktop task.
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot(), nil]
    let r = harnessRig(FakeResolver([step("wait", .continue, [.wait(ms: 100)]), step("done", .done)]), harness: h)
    _ = await r.runner.run(goal: "x", mode: .command)
    #expect(r.resolver.requests.map(\.observation.harness) == [.agentDesktop, .agentDesktop])
    #expect(r.resolver.requests[1].observation.elements.first?.title == "Reload")   // native fallback elements
    // No snapshot on step 1: a native task; the harness is not asked again.
    let h2 = FakeHarness(); h2.snapshotResults = [nil, harnessSnapshot()]
    let r2 = harnessRig(FakeResolver([step("wait", .continue, [.wait(ms: 100)]), step("done", .done)]), harness: h2)
    _ = await r2.runner.run(goal: "x", mode: .command)
    #expect(r2.resolver.requests.map(\.observation.harness) == [.native, .native])
    #expect(h2.calls.filter { $0.hasPrefix("snapshot") }.count == 1)
}
