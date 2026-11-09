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

/// What `onStatus` reported, in order (the prompt's row as the user reads it).
@MainActor private final class StatusLog {
    var texts: [String] = []
    var trails: [TaskTrail] = []
}

@MainActor private struct Rig {
    var runner: TaskRunner
    var log: StatusLog
    var statuses: [String] { log.texts }
    var resolver: FakeResolver
    var input: FakeInput
    var ax: FakeElements
    var overlay: FakeOverlay
    var typed: [String] { input.calls.filter { $0.hasPrefix("type:") } }
    var releaseAllCalls: Int { input.calls.filter { $0 == "releaseAll" }.count }
}

@MainActor private func rig(_ resolver: FakeResolver, maxSteps: Int = 12, settleMs: Int = 3000) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay(), audio = FakeAudio()
    ax.front = "Safari"
    ax.elements = [el(1, "Reload")]
    var config = AppConfig()
    config.maxTaskSteps = maxSteps
    config.settleMs = settleMs
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config, frontTimeout: .milliseconds(100), audio: audio)
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: config.maxObservedElements, audio: audio),
                            overlay: overlay, sleep: { _ in })
    let log = StatusLog()
    runner.onStatus = { log.texts.append($0.text) }
    runner.onTrail = { log.trails.append($0) }
    return Rig(runner: runner, log: log, resolver: resolver, input: input, ax: ax, overlay: overlay)
}

private func step(_ intent: String, _ status: StepStatus, _ actions: [Action] = []) -> IntentStep {
    IntentStep(intent: intent, status: status, actions: actions)
}

@MainActor @Test func trailFollowsTheTask() async {
    typealias S = TaskStepRecord.State
    func scrolls(_ n: Int) -> [IntentStep] { (1...n).map { step("scroll \($0)", .continue, [.scroll(.down, amount: $0)]) } }
    // (goal, steps, maxSteps, states at the end, ending, the trail's cap)
    let table: [(String, [IntentStep], Int, [S], TaskTrail.Ending?, Int)] = [
        ("type hi", [step("open", .continue, [.typeText("a")]), step("type", .done, [.typeText("hi")])], 12, [.done, .done], nil, 12),
        ("open nope", [step("open it", .continue, [.openApp("Nope")]), step("type", .done, [.typeText("hi")])], 12,
         [.failed("no app named Nope"), .done], nil, 12),
        ("scroll forever", scrolls(5), 3, [.done, .done, .done], .stepCap, 3),
        ("press it", [step("one", .continue, [.typeText("a")]), step("hmm", .stuck)], 12, [.done], .stuck, 12),
        ("watch cats on youtube", [step("playing", .done)], 12, [.done], nil, AppConfig().maxMediaTaskSteps),
    ]
    for (goal, steps, maxSteps, states, ending, cap) in table {
        let r = rig(FakeResolver(steps), maxSteps: maxSteps)
        _ = await r.runner.run(goal: goal, mode: .command)
        #expect(r.log.trails.first == TaskTrail(maxSteps: cap), "\(goal)")   // each run starts from the empty trail
        let last = r.log.trails.last
        #expect(last?.steps.map(\.state) == states, "\(goal)")
        #expect(last?.ending == ending, "\(goal)")
        #expect(last?.maxSteps == cap, "\(goal)")
    }

    // A step cut short by stop stays running, so the panel shows it as stopped and not failed.
    let r = rig(FakeResolver([step("wait then type", .continue, [.wait(ms: 5000), .typeText("late")])]))
    let runner = r.runner
    let task = Task { await runner.run(goal: "slow", mode: .command) }
    try? await Task.sleep(for: .milliseconds(100))
    runner.cancel()
    #expect(await task.value == .stopped)
    #expect(r.log.trails.last?.steps.map(\.state) == [.running])
    #expect(r.log.trails.last?.ending == nil)
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
    #expect(r.statuses == ["step 1 · type hi", "done · type hi (1 step)"])
    #expect(r.releaseAllCalls == 0)
}

@MainActor @Test func doneWithEmptyIntentShowsPlainDone() async {
    let r = rig(FakeResolver([step("", .done)]))
    #expect(await r.runner.run(goal: "x", mode: .command) == .done(""))
    #expect(r.statuses.last == "done (1 step)")
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
    #expect(r.statuses == ["step 1 · open search", "step 2 · finished", "done · finished (2 steps)"])
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
    #expect(r.statuses == ["step 1 · open it", "step 1 · open it ✗ no app named Nope", "stuck: gave up (1 step)"])
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
    #expect(r.statuses.last == "stuck: step limit reached (3 steps)")
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
    #expect(r.statuses.last == "stopped (1 step)")
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
    #expect(r.statuses == ["timed out"])
    #expect(r.releaseAllCalls == 1)
}

@MainActor @Test func ignoreRunsNothing() async {
    let r = rig(FakeResolver([step("chatter", .ignore, [.typeText("no")])]))
    #expect(await r.runner.run(goal: "hello there", mode: .command) == .ignored)
    #expect(r.input.calls == ["releaseAll"])
    #expect(r.statuses == [PipelineText.didntCatch])
}

@MainActor @Test func stuckRunsNothing() async {
    let r = rig(FakeResolver([step("no such button", .stuck, [.typeText("no")])]))
    #expect(await r.runner.run(goal: "press it", mode: .command) == .stuck("no such button"))
    #expect(r.input.calls == ["releaseAll"])
    #expect(r.statuses == ["stuck: no such button"])
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
    #expect(r.statuses.last == "stuck: repeating the same action (2 steps)")
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
    #expect(r.statuses.last == "stopped: cannot find the button (1 step)")
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

@MainActor private func harnessRig(_ resolver: FakeResolver, harness: FakeHarness, trace: Bool = false, settleMs: Int = 0) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    ax.front = "Safari"
    ax.elements = [el(1, "Reload")]
    var config = AppConfig()
    config.settleMs = settleMs
    config.agentDesktopTrace = trace
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config, frontTimeout: .milliseconds(100),
                                  harness: harness, clipboard: FakeClipboard())
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120, harness: harness),
                            overlay: overlay, sleep: { _ in }, harness: harness)
    let log = StatusLog()
    runner.onStatus = { log.texts.append($0.text) }
    runner.onTrail = { log.trails.append($0) }
    return Rig(runner: runner, log: log, resolver: resolver, input: input, ax: ax, overlay: overlay)
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
    #expect(r.statuses.last == "read it — clipboard: hello world (1 step)")
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

@MainActor @Test func openSurfaceSurvivesTheSettlePolls() async {
    // The click leaves a sheet open; every settle poll must snapshot the sheet, and the model must see it.
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.surfacesAfterAct = ["sheet"]
    let r = harnessRig(FakeResolver([step("click", .continue, [.click(.label(1), button: .left, count: 1)]), step("done", .done)]),
                       harness: h, settleMs: 3000)
    _ = await r.runner.run(goal: "save it", mode: .command)
    #expect(r.resolver.requests.count == 2)
    #expect(r.resolver.requests[1].observation.surface == "sheet")
    let polls = h.calls.filter { $0.hasPrefix("snapshot:") }
    #expect(polls.first == "snapshot:Safari" && polls.dropFirst().allSatisfy { $0 == "snapshot:sheet" } && polls.count >= 3)
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

private func tab(_ id: String, _ title: String, active: Bool = false) -> BrowserTab { BrowserTab(id: id, title: title, active: active) }

@MainActor @Test func taskClosesAPopUnderTabButNeverTheUsersOwn() async throws {
    let resolver = FakeResolver([
        step("open the game", .continue, [.openURL(URL(string: "https://stream.example")!, app: nil)]),
        step("close the pop-under", .continue, [.closeTab(3)]),
        step("close the inbox", .continue, [.closeTab(1)]),
        step("playing", .done)])
    let r = rig(resolver)
    r.ax.browser = [BrowserWindow(id: "w1", title: "Inbox", front: true, tabs: [tab("t1", "Inbox", active: true)])]
    let ax = r.ax
    ax.browserApp = "Google Chrome"
    // The open_url step leaves the game in a new active tab and a pop-under behind it.
    let afterOpen = [BrowserWindow(id: "w1", title: "Game", front: true,
                                   tabs: [tab("t1", "Inbox"), tab("t2", "Game", active: true), tab("t3", "You won!")])]
    resolver.onResolve = { n in if n == 1 { ax.browser = afterOpen } }
    let outcome = await r.runner.run(goal: "watch the Raptors game", mode: .command)
    #expect(outcome == .done("playing"))
    let second = try #require(resolver.requests[1].observation.tabs)
    #expect(second.tab(2)?.new == true && second.tab(2)?.task == true)
    #expect(second.tab(3)?.new == true && second.tab(1)?.new == false)
    #expect(second.app == "Google Chrome")   // the ledger and the list name the app the windows were read from
    #expect(ax.closedTabs == ["t3"])
    #expect(resolver.requests[3].history[2].failure == "blocked: tab 1 is not one this task opened")
    // A media goal gets the longer step cap.
    #expect(resolver.requests[0].maxSteps == 24)
}

@MainActor @Test func aBrowserFirstSeenLateIsBaselinedBeforeTheNextStepSoItsPopUpIsNew() async throws {
    let resolver = FakeResolver([step("click play", .continue, [.wait(ms: 1)]), step("look", .continue, [.wait(ms: 1)]), step("done", .done)])
    let r = rig(resolver)   // the front app is not a browser at the task's start
    let ax = r.ax
    let user = BrowserWindow(id: "w1", title: "Inbox", front: true, tabs: [tab("t1", "Inbox", active: true)])
    resolver.onResolve = { n in
        if n == 1 { ax.browser = [user] }   // the browser comes up during the first step
        if n == 2 { ax.browser = [BrowserWindow(id: "w1", title: "Inbox", front: true, tabs: [tab("t1", "Inbox", active: true)]),
                                  BrowserWindow(id: "w2", title: "Casino", tabs: [tab("c1", "Casino")])] }   // 'click play' opened a pop-up
    }
    _ = await r.runner.run(goal: "x", mode: .command)
    let seen = try #require(resolver.requests[1].observation.tabs)
    #expect(seen.windows.count == 1 && seen.tab(1)?.new == false)
    let popped = try #require(resolver.requests[2].observation.tabs)
    #expect(popped.window(2)?.new == true && popped.tab(2)?.new == true)
}

@MainActor @Test func aNavigationThatFailedMarksNoTaskTab() async throws {
    let resolver = FakeResolver([step("open the game", .continue, [.openURL(URL(string: "https://stream.example")!, app: "Nonesuch")]),
                                 step("look", .done)])
    let r = rig(resolver)   // no app named Nonesuch: the step fails
    r.ax.browser = [BrowserWindow(id: "w1", title: "Inbox", front: true, tabs: [tab("t1", "Inbox", active: true)])]
    let ax = r.ax
    resolver.onResolve = { n in
        if n == 1 { ax.browser = [BrowserWindow(id: "w1", title: "Game", front: true, tabs: [tab("t1", "Inbox"), tab("t2", "Game", active: true)])] }
    }
    _ = await r.runner.run(goal: "x", mode: .command)
    let seen = try #require(resolver.requests[1].observation.tabs)
    #expect(resolver.requests[1].history.first?.failure != nil)
    #expect(seen.tab(2)?.new == true && seen.tab(2)?.task == false)
}

@MainActor @Test func playGoalIsDoneOnlyWhenMediaPlays() async {
    func button(_ title: String) -> [UIElementInfo] { [el(1, title)] }
    let done = step("started it", .done)
    // (goal, element titles on screen, titles after the first resolve, steps, outcome, requests, re-asked once)
    let table: [(String, [String], [String]?, [IntentStep], TaskOutcome, Int, Bool)] = [
        ("play the video", ["Play"], nil, [done], .stuck("not playing yet"), 2, true),
        ("play the video", ["Play"], ["Pause (k)"], [done], .done("started it"), 2, true),
        ("watch veritasium", ["Reload"], nil, [done], .done("started it"), 1, false),
        ("scroll down", ["Play"], nil, [done], .done("started it"), 1, false),
    ]
    for (goal, shown, later, steps, outcome, requests, reasked) in table {
        let resolver = FakeResolver(steps)
        let r = rig(resolver)
        r.ax.elements = shown.enumerated().map { el($0.offset + 1, $0.element) }
        if let later {
            let ax = r.ax
            resolver.onResolve = { n in if n == 2 { ax.elements = later.enumerated().map { el($0.offset + 1, $0.element) } } }
        }
        #expect(await r.runner.run(goal: goal, mode: .command) == outcome, "\(goal) \(shown)")
        #expect(resolver.requests.count == requests, "\(goal) \(shown)")
        if reasked {
            #expect(resolver.requests[1].history == [StepRecord(intent: "started it", actions: [], failure: "not playing yet")])
            #expect(resolver.requests[1].observation.media == .paused)
        }
    }
}
