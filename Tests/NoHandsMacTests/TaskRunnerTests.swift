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
    /// The scripted answer to `plan(goal:)` (nil result: no plan), the goals it was asked about, and a hook run first.
    var planResult: Result<TaskPlan?, IntentError> = .success(nil)
    var planGoals: [String] = []
    var onPlan: (@Sendable () async -> Void)?
    func plan(goal: String) async throws -> TaskPlan? {
        planGoals.append(goal)
        await onPlan?()
        return try planResult.get()
    }
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
    var statuses: [String] { log.texts.filter { !isPhaseLine($0) } }
    var resolver: FakeResolver
    var input: FakeInput
    var ax: FakeElements
    var overlay: FakeOverlay
    var screenshots: FakeScreenshots?
    var typed: [String] { input.calls.filter { $0.hasPrefix("type:") } }
    var releaseAllCalls: Int { input.calls.filter { $0 == "releaseAll" }.count }
}

@MainActor private func rig(_ resolver: FakeResolver, maxSteps: Int = 12, settleMs: Int = 3000,
                            vision: FakeScreenshots? = nil, visionFlag: Bool = true,
                            sleep: @escaping @Sendable (Duration) async -> Void = { _ in }) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay(), audio = FakeAudio()
    ax.front = "Safari"
    ax.elements = [el(1, "Reload")]
    var config = AppConfig()
    config.maxTaskSteps = maxSteps
    config.settleMs = settleMs
    config.visionFallback = visionFlag
    config.intentBackend = .claude
    config.anthropicAPIKey = "test-key"
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config, frontTimeout: .milliseconds(100), audio: audio)
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: config.maxObservedElements, audio: audio),
                            overlay: overlay, sleep: sleep, screenshots: vision)
    let log = StatusLog()
    runner.onStatus = { log.texts.append($0.text) }
    runner.onTrail = { log.trails.append($0) }
    return Rig(runner: runner, log: log, resolver: resolver, input: input, ax: ax, overlay: overlay, screenshots: vision)
}

private func step(_ intent: String, _ status: StepStatus, _ actions: [Action] = []) -> IntentStep {
    IntentStep(intent: intent, status: status, actions: actions)
}

/// The phase the runner reports at each emission, collapsed so a repeat reads once.
@MainActor private func phases(_ log: StatusLog) -> [TaskPhase?] {
    var out: [TaskPhase?] = []
    for t in log.trails where out.last != .some(t.phase) { out.append(t.phase) }
    return out
}

@MainActor @Test func phasesFollowTheTask() async {
    typealias P = TaskPhase
    let click = Action.click(.cursor, button: .left, count: 1)
    let table: [(String, [IntentStep], [P?], [String])] = [
        ("one model step", [step("go", .done, [click])], [.reading, .thinking, .acting, .reading, nil],
         ["Reading · looking at the screen", "Thinking · working out the first step"]),
        ("two model steps", [step("a", .continue, [click]), step("b", .done, [click])],
         [.reading, .thinking, .acting, .reading, .thinking, .acting, .reading, nil],
         ["Reading · looking at the screen", "Thinking · working out the first step"]),
        ("stuck", [step("hmm", .stuck)], [.reading, .thinking, nil],
         ["Reading · looking at the screen", "Thinking · working out the first step"]),
    ]
    for (goal, steps, want, rows) in table {
        let r = rig(FakeResolver(steps))
        _ = await r.runner.run(goal: goal, mode: .command)
        #expect(phases(r.log) == want, "\(goal)")
        #expect(r.log.texts.filter(isPhaseLine) == rows, "\(goal)")   // the board row, before the first step only
    }
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
        var start = TaskTrail(maxSteps: cap)
        start.phase = .reading
        #expect(r.log.trails.first == start, "\(goal)")   // each run starts from the empty trail, reading
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
    #expect(r.log.trails.last?.phase == nil)   // a stop ends the phase: the panel has nothing to animate
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
    let resolver = FakeResolver([step("go to the url", .continue, [.pressKey(KeyChord(.w, [.command])), .typeText("cats")]),
                                 step("gave up", .stuck)])
    let r = rig(resolver)
    #expect(await r.runner.run(goal: "open the latest video", mode: .command) == .stuck("gave up"))
    #expect(r.input.calls.allSatisfy { $0 == "releaseAll" })   // nothing typed or pressed
    #expect(resolver.requests[1].history == [StepRecord(
        intent: "go to the url", actions: [.pressKey(KeyChord(.w, [.command])), .typeText("cats")],
        failure: "blocked: command-w not allowed for this request")])
}

@MainActor @Test func typedAddressIsOpenedAndMenuBarClicksAreRefused() async {
    // A typed web address runs as open_url (its Return dropped) and History records what ran.
    let url = URL(string: "https://youtube.com/@x/videos")!
    let typed = FakeResolver([step("go to the channel", .continue, [.typeText("youtube.com/@x/videos"), .pressKey(KeyChord(.return))]),
                              step("done", .done)])
    let a = rig(typed)
    #expect(await a.runner.run(goal: "open the latest video", mode: .command) == .done("done"))
    #expect(a.ax.opened.map(\.url) == [url])
    #expect(a.input.calls.allSatisfy { $0 == "releaseAll" })   // nothing typed or pressed
    #expect(typed.requests[1].history.map(\.actions) == [[.openURL(url, app: nil)]])

    // The menu bar is numbered after the page, and a click on its item runs nothing and is recorded as a failure.
    let click: Action = .click(.label(2), button: .left, count: 1)
    let bar = FakeResolver([step("click edit", .continue, [click]), step("gave up", .stuck)])
    let b = rig(bar)
    b.ax.elements = [UIElementInfo(id: 0, frame: CGRect(x: 0, y: 0, width: 40, height: 20), title: "Edit", role: "AXMenuBarItem"),
                     UIElementInfo(id: 0, frame: CGRect(x: 0, y: 200, width: 80, height: 30), title: "Videos", role: "AXLink")]
    #expect(await b.runner.run(goal: "open the latest video", mode: .command) == .stuck("gave up"))
    #expect(bar.requests[0].observation.elements.map(\.title) == ["Videos", "Edit"])   // the page first
    #expect(b.input.calls.allSatisfy { $0 == "releaseAll" })
    #expect(bar.requests[1].history == [StepRecord(
        intent: "click edit", actions: [click], failure: "label 2 is the \"Edit\" menu bar item, not a page element")])
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

@MainActor private func harnessRig(_ resolver: FakeResolver, harness: FakeHarness, trace: Bool = false, settleMs: Int = 0,
                                   vision: FakeScreenshots? = nil, clock: FakeClock = FakeClock(),
                                   sleep: @escaping @Sendable (Duration) async -> Void = { _ in }) -> Rig {
    let input = FakeInput(), ax = FakeElements(), overlay = FakeOverlay()
    ax.front = "Safari"
    ax.elements = [el(1, "Reload")]
    var config = AppConfig()
    config.settleMs = settleMs
    config.agentDesktopTrace = trace
    config.visionFallback = vision != nil
    config.intentBackend = .claude
    config.anthropicAPIKey = "test-key"
    let executor = ActionExecutor(input: input, ax: ax, overlay: overlay, config: config, frontTimeout: .milliseconds(100),
                                  harness: harness, clipboard: FakeClipboard())
    let runner = TaskRunner(config: config, resolver: resolver, executor: executor,
                            observer: ScreenObserver(ax: ax, maxElements: 120, harness: harness),
                            overlay: overlay, sleep: sleep, now: { clock.now() }, harness: harness, screenshots: vision)
    let log = StatusLog()
    runner.onStatus = { log.texts.append($0.text) }
    runner.onTrail = { log.trails.append($0) }
    return Rig(runner: runner, log: log, resolver: resolver, input: input, ax: ax, overlay: overlay, screenshots: vision)
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

@MainActor @Test func pageTextReachesTheNextRequestOnceAndEmptyPagesFailTheStep() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]
    let r = harnessRig(FakeResolver([step("read", .continue, [.readPage]), step("look", .continue, [.wait(ms: 100)]),
                                     step("done", .done)]), harness: h)
    r.ax.pageRuns = ["Raptors vs Celtics", "7:30 PM", "Watch"]
    #expect(await r.runner.run(goal: "open the raptors game", mode: .command) == .done("done"))
    #expect(r.resolver.requests.map(\.observation.readings) == [[], ["page: Raptors vs Celtics | 7:30 PM | Watch"], []])
    let empty = harnessRig(FakeResolver([step("read", .continue, [.readPage]), step("stuck", .stuck)]), harness: h)
    _ = await empty.runner.run(goal: "open the raptors game", mode: .command)
    #expect(empty.resolver.requests[1].history.first?.failure == ActionExecutor.noPageText)
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

@MainActor private final class TaskBox { var task: Task<TaskOutcome, Never>? }

@MainActor @Test func stoppingATracedTaskStillEndsItsSession() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]
    let resolver = FakeResolver([step("wait", .continue, [.wait(ms: 5000)])])
    let r = harnessRig(resolver, harness: h, trace: true)
    let runner = r.runner, box = TaskBox()
    resolver.onResolve = { _ in await box.task?.cancel() }
    box.task = Task { await runner.run(goal: "slow", mode: .command) }
    #expect(await box.task!.value == .stopped)
    #expect(h.calls.last == "session:end:sess-1")
    #expect(h.sessionEndedCancelled == false)
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

// MARK: vision fallback

private let seesScreen = "step 2 · looking at the screen"

@MainActor @Test func aPictureIsTakenOnlyWhereTheTreeFailed() async {
    let namedClick = Action.click(.element(named: "Play"), button: .left, count: 1)
    let click1 = Action.click(.label(1), button: .left, count: 1)
    // (steps, picture on request 2?, captures, the flag, the strings VisionTrigger matches are what the executor says)
    let table: [(String, [IntentStep], Bool, Int, Bool)] = [
        ("named click that fails", [step("play", .continue, [namedClick]), step("done", .done)], true, 1, true),
        ("a step that worked", [step("click", .continue, [click1]), step("done", .done)], false, 0, true),
        ("look", [step("look", .continue, [.look]), step("done", .done)], true, 1, true),
        ("flag off", [step("play", .continue, [namedClick]), step("done", .done)], false, 0, false),
    ]
    for (name, steps, picture, captures, flag) in table {
        let fake = FakeScreenshots()
        let r = rig(FakeResolver(steps), vision: fake, visionFlag: flag)
        _ = await r.runner.run(goal: "play it", mode: .command)
        let sent = r.resolver.requests.map(\.vision)
        #expect(fake.calls == captures, "\(name)")
        #expect((sent[1] != nil) == picture, "\(name)")
        #expect(sent[0] == nil && sent.dropFirst(2).allSatisfy { $0 == nil }, "\(name)")
        if picture { #expect(r.statuses.contains(seesScreen), "\(name)") }
    }
    // The failure the executor really produces, and its own stale-element text, are what the trigger matches.
    let r = rig(FakeResolver([step("play", .continue, [namedClick]), step("done", .done)]), vision: FakeScreenshots())
    _ = await r.runner.run(goal: "play it", mode: .command)
    let failure = r.resolver.requests[1].history[0].failure
    #expect(failure?.hasPrefix("no element named") == true)
    #expect(VisionTrigger.wantsPicture(lastFailure: failure, lastActions: [namedClick]))
    #expect(VisionTrigger.wantsPicture(lastFailure: ActionExecutor.elementChanged, lastActions: []))
    // No provider at all: the same task, no picture.
    let none = rig(FakeResolver([step("play", .continue, [namedClick]), step("done", .done)]))
    _ = await none.runner.run(goal: "play it", mode: .command)
    #expect(none.resolver.requests.allSatisfy { $0.vision == nil })
}

@MainActor @Test func lookKeepsTheBadgesUpAndOtherActingStepsHideThem() async {
    let badges: [Int: UIElementInfo] = [1: el(1, "Reload")]
    let fake = FakeScreenshots()
    let r = rig(FakeResolver([step("look", .continue, [.look]), step("done", .done)]), vision: fake)
    r.overlay.state = .labels(badges)
    _ = await r.runner.run(goal: "play it", mode: .command)
    #expect(fake.badges == [badges])
    let acted = rig(FakeResolver([step("scroll", .continue, [.scroll(.down, amount: 1)]), step("done", .done)]), vision: FakeScreenshots())
    acted.overlay.state = .labels(badges)
    _ = await acted.runner.run(goal: "scroll", mode: .command)
    #expect(acted.overlay.state == .none)
}

@MainActor @Test func stuckWithoutAPictureLooksOnceAndAsksAgain() async {
    let stuck = step("cannot find it", .stuck)
    let image = ScreenshotResult.image(FakeScreenshots.shot)
    // (steps, capture result, requests, captures, outcome, steps run)
    let table: [(String, [IntentStep], ScreenshotResult, Int, Int, TaskOutcome, Int)] = [
        ("a picture helps", [stuck, step("clicked it", .done, [.typeText("x")])], image, 2, 1, .done("clicked it"), 1),
        ("stuck even with a picture", [stuck], image, 2, 1, .stuck("cannot find it"), 0),
        ("no grant", [stuck], .notGranted, 1, 1, .stuck("cannot find it (screen recording not granted)"), 0),
        ("capture failed", [stuck], .failed, 1, 1, .stuck("cannot find it (screen capture failed)"), 0),
    ]
    for (name, steps, result, requests, captures, outcome, stepsRun) in table {
        let fake = FakeScreenshots([result])
        let r = rig(FakeResolver(steps), vision: fake)
        #expect(await r.runner.run(goal: "play it", mode: .command) == outcome, "\(name)")
        #expect(r.resolver.requests.count == requests && fake.calls == captures, "\(name)")
        #expect(r.runner.stepsRun == stepsRun, "\(name)")
        if requests == 2 {
            #expect(r.resolver.requests.map(\.step) == [1, 1] && r.resolver.requests[0].vision == nil, "\(name)")
            #expect(r.resolver.requests[1].vision == .image(FakeScreenshots.shot), "\(name)")
        }
    }
    // Stuck on a request that already said why there was no picture ends the task: no capture, no second call.
    let namedClick = Action.click(.element(named: "Play"), button: .left, count: 1)
    let fake = FakeScreenshots([.notGranted])
    let r = rig(FakeResolver([step("play", .continue, [namedClick]), stuck]), vision: fake)
    #expect(await r.runner.run(goal: "play it", mode: .command) == .stuck("cannot find it"))
    #expect(r.resolver.requests.count == 2 && fake.calls == 1)
}

@MainActor @Test func noPictureStepsSayWhyAndTheTaskGoesOn() async {
    let rows: [(ScreenshotResult, String)] = [(.notGranted, "screen recording not granted"), (.failed, "screen capture failed")]
    for (result, why) in rows {
        let r = rig(FakeResolver([step("look", .continue, [.look]), step("done", .done)]), vision: FakeScreenshots([result]))
        #expect(await r.runner.run(goal: "play it", mode: .command) == .done("done"), "\(why)")
        #expect(r.resolver.requests[1].vision == .unavailable(why), "\(why)")
        #expect(r.statuses.contains("step 2 · \(why)"), "\(why)")
    }
    // A menu or sheet is open: no capture at all, the element list already shows it.
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.surfacesAfterAct = ["sheet"]
    let fake = FakeScreenshots()
    let r = harnessRig(FakeResolver([step("open", .continue, [.click(.label(1), button: .left, count: 1), .look]), step("done", .done)]),
                       harness: h, settleMs: 3000, vision: fake)
    _ = await r.runner.run(goal: "save it", mode: .command)
    #expect(fake.calls == 0)
    #expect(r.resolver.requests[1].vision == .unavailable("a menu or sheet is open"))
    #expect(r.statuses.contains("step 2 · a menu or sheet is open"))
}

@MainActor @Test func pictureClicksAreMappedAndCheckedBeforeActing() async {
    let point = { (x: CGFloat, y: CGFloat) in Action.click(.point(CGPoint(x: x, y: y)), button: .left, count: 1) }
    // (actions on the picture step, window moved before acting, clicks, the failure the model is told)
    let table: [(String, [Action], Bool, [String], String?)] = [
        ("mapped to the screen", [point(100, 50)], false, ["click:300,200"], nil),
        ("a click after another action", [.wait(ms: 0), point(100, 50)], false, [], ScreenshotGeometry.notFirstReason),
        ("past the picture", [point(500, 50)], false, [], ScreenshotGeometry.outsideReason),
        ("window moved", [point(100, 50)], true, [], ActionExecutor.elementChanged),
        ("window within tolerance", [point(100, 50)], false, ["click:300,200"], nil),
    ]
    for (name, actions, moves, clicks, failure) in table {
        let resolver = FakeResolver([step("look", .continue, [.look]), step("click it", .continue, actions), step("done", .done)])
        let r = rig(resolver, vision: FakeScreenshots())
        let ax = r.ax
        resolver.onResolve = { n in
            if n == 2 { ax.windowFrame = moves ? CGRect(x: 160, y: 100, width: 400, height: 300) : CGRect(x: 101, y: 99, width: 400, height: 300) }
        }
        _ = await r.runner.run(goal: "play it", mode: .command)
        #expect(r.input.calls.filter { $0.hasPrefix("click:") } == clicks, "\(name)")
        #expect(resolver.requests[2].history[1].failure == failure, "\(name)")
        #expect(resolver.requests[2].history[1].actions == actions, "\(name)")   // history keeps what the model sent
    }
    // With vision on, a point on a step with no picture is refused (it would be a raw screen point), and the model gets
    // a picture next step. With no provider (vision off) it is a screen point, untouched.
    let resolver = FakeResolver([step("click", .continue, [point(100, 50)]), step("done", .done)])
    let on = rig(resolver, vision: FakeScreenshots())
    _ = await on.runner.run(goal: "click", mode: .command)
    #expect(on.input.calls.filter { $0.hasPrefix("click:") }.isEmpty)
    #expect(resolver.requests[1].history[0].failure == ScreenshotGeometry.needsPictureReason)
    #expect(resolver.requests[1].vision == .image(FakeScreenshots.shot))
    let off = rig(FakeResolver([step("click", .done, [point(100, 50)])]))
    _ = await off.runner.run(goal: "click", mode: .command)
    #expect(off.input.calls.filter { $0.hasPrefix("click:") } == ["click:100,50"])
}

@MainActor @Test func aHungCaptureNeverDelaysStopOrTheStep() async {
    let namedClick = Action.click(.element(named: "Play"), button: .left, count: 1)
    // Stop while the capture hangs: the task ends stopped at once.
    let hung = FakeScreenshots(); hung.hangs = true
    let r = rig(FakeResolver([step("play", .continue, [namedClick]), step("done", .done)]), vision: hung)
    let runner = r.runner
    let task = Task { await runner.run(goal: "play it", mode: .command) }
    for _ in 0..<200 where hung.calls == 0 { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(hung.calls == 1)
    let start = ContinuousClock.now
    runner.cancel()
    #expect(await task.value == .stopped)
    #expect(start.duration(to: .now) < .seconds(1))
    // Without a stop the deadline ends the wait: the step goes on with no picture.
    let slow = FakeScreenshots(); slow.hangs = true
    let late = rig(FakeResolver([step("play", .continue, [namedClick]), step("done", .done)]), vision: slow)
    late.runner.captureDeadline = .milliseconds(100)
    #expect(await late.runner.run(goal: "play it", mode: .command) == .done("done"))
    #expect(late.resolver.requests[1].vision == .unavailable("screen capture failed"))
}


// MARK: model-written plans

private let planGoal = "play the maple video on clipbox"

private func planStep(_ kind: PlanStepKind, _ check: PlanCheck, site: String? = nil, text: String? = nil) -> PlanStep {
    PlanStep(intent: "plan \(kind.rawValue)", kind: kind, site: site, text: text, check: check)
}
private let openMaple = planStep(.openSite, PlanCheck(kind: .elementPresent, text: "Maple"), site: "github.com")
private let clickMaple = planStep(.click, PlanCheck(kind: .elementPresent, text: "Maple"), text: "Maple")
private let playing = planStep(.waitForMedia, PlanCheck(kind: .mediaPlaying))
private let pageHasMaple = [el(1, "Maple"), el(2, "Pause (k)")]

@MainActor @Test func aValidPlanRunsWithoutAskingTheModelAndEndsDone() async {
    let resolver = FakeResolver([step("never asked", .done)])
    resolver.planResult = .success(TaskPlan(steps: [openMaple, clickMaple, playing]))
    let r = rig(resolver)
    r.ax.defaultBrowser = "Safari"
    r.ax.elements = pageHasMaple
    #expect(await r.runner.run(goal: planGoal, mode: .command) == .done("plan wait_for_media"))
    #expect(resolver.planGoals == [planGoal])
    #expect(resolver.requests.isEmpty)
    #expect(r.input.calls.filter { $0.hasPrefix("click") }.count == 1)
    #expect(r.runner.stepsRun == 4)   // three plan steps, then the finish step
    // planning, then no model call (no thinking) between plan steps
    #expect(phases(r.log).prefix(3) == [.reading, .planning, .acting] && !phases(r.log).contains(.thinking))
    #expect(r.log.texts.filter(isPhaseLine) == ["Reading · looking at the screen", "Thinking · planning the steps"])
}

@MainActor @Test func aPlanThatMissesHandsOverToTheModelWithItsStepsAsHistory() async {
    let blocked = "no browser for github.com"
    // (the plan, the executor's browser, the failure the model's History ends with, the History length)
    let table: [([PlanStep], String?, String, Int)] = [
        ([openMaple, planStep(.click, PlanCheck(kind: .elementPresent, text: "Maple banner"), text: "Maple"), playing], "Safari",
         "plan step 2 did not reach its element_present check", 3),
        ([openMaple, playing], nil, blocked, 1),
    ]
    for (steps, browser, failure, length) in table {
        let resolver = FakeResolver([step("took over", .done)])
        resolver.planResult = .success(TaskPlan(steps: steps))
        let r = rig(resolver)
        r.ax.defaultBrowser = browser
        r.ax.elements = pageHasMaple + (3...300).map { el($0, "Filler \($0)") }
        #expect(await r.runner.run(goal: planGoal, mode: .command) == .done("took over"), "\(failure)")
        let asked = resolver.requests.first
        #expect(asked?.history.count == length, "\(failure)")
        #expect(asked?.history.last?.failure == failure)
        // The plan read up to 200 elements; the model is sent the normal cap.
        #expect(asked?.observation.elements.count == AppConfig().maxObservedElements, "\(failure)")
    }
}

@MainActor @Test func aPlanThatCannotBeUsedRunsTheNormalLoop() async {
    let usable = TaskPlan(steps: [openMaple, clickMaple, playing])
    let noTie = TaskPlan(steps: [planStep(.openSite, PlanCheck(kind: .elementPresent, text: "Sign in"), site: "github.com"), playing])
    // (goal, what plan(goal:) answers, whether it is asked at all)
    let table: [(String, Result<TaskPlan?, IntentError>, Bool)] = [
        (planGoal, .success(nil), true),
        (planGoal, .failure(.timeout), true),
        (planGoal, .failure(.network(Boom())), true),
        (planGoal, .success(noTie), true),
        ("play it", .success(usable), false),
        ("play the maple video in safari", .success(usable), false),
        ("scroll down on this page a little", .success(usable), false),
    ]
    for (goal, answer, asked) in table {
        let resolver = FakeResolver([step("looped", .done)])
        resolver.planResult = answer
        let r = rig(resolver)
        r.ax.elements = pageHasMaple
        #expect(await r.runner.run(goal: goal, mode: .command) == .done("looped"), "\(goal)")
        #expect(resolver.planGoals.count == (asked ? 1 : 0), "\(goal)")
        #expect(resolver.requests.count == 1 && resolver.requests[0].history.isEmpty, "\(goal)")
    }
}

@MainActor @Test func stopEndsAPlanWhileItIsBeingAskedForAndWhileItRuns() async {
    let resolver = FakeResolver([step("never", .done)])
    resolver.planResult = .success(TaskPlan(steps: [openMaple, clickMaple, playing]))
    let r = rig(resolver)
    r.ax.elements = [el(1, "Maple")]
    let runner = r.runner
    resolver.onPlan = { await runner.cancel() }
    #expect(await runner.run(goal: planGoal, mode: .command) == .stopped)
    #expect(resolver.requests.isEmpty && r.input.calls.filter { $0.hasPrefix("click") }.isEmpty)

    // Mid-plan: nothing plays, so the wait step would run 20 s; stop ends it at once and runs no more.
    let waiting = FakeResolver([step("never", .done)])
    waiting.planResult = .success(TaskPlan(steps: [openMaple, clickMaple, playing]))
    let w = rig(waiting)
    w.ax.defaultBrowser = "Safari"
    w.ax.elements = [el(1, "Maple")]
    let task = Task { await w.runner.run(goal: planGoal, mode: .command) }
    try? await Task.sleep(for: .milliseconds(200))
    w.runner.cancel()
    let start = ContinuousClock.now
    #expect(await task.value == .stopped)
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(waiting.requests.isEmpty)
}

private func resolverForSend() -> FakeResolver {
    FakeResolver([step("send it", .done, [.click(.label(1), button: .left, count: 1)])])
}

@MainActor @Test func irreversibleStepWaitsForASpokenYes() async {
    enum Reply { case say(String), stop, silence, notNeeded }
    // The answer wait's timeout never fires on its own here; the other sleeps (settling) return at once.
    let holdTimeout: @Sendable (Duration) async -> Void = { d in
        if d == TaskRunner.answerTimeout { try? await Task.sleep(for: .seconds(30)) }
    }
    // (goal, what the user does, outcome, whether the click ran, the row's last line)
    let table: [(String, Reply, TaskOutcome, Bool, String)] = [
        ("reply to Anna", .say("yes"), .done("send it"), true, "done · send it (1 step)"),
        ("reply to Anna", .say("no"), .stopped, false, "stopped: send not confirmed"),
        ("reply to Anna", .say("yes and also open Safari"), .stopped, false, "stopped: send not confirmed"),
        ("reply to Anna", .silence, .stopped, false, "stopped: send not confirmed"),
        ("reply to Anna", .stop, .stopped, false, PipelineText.stopped),
        ("send the reply", .notNeeded, .done("send it"), true, "done · send it (1 step)"),
    ]
    for (goal, reply, outcome, clicked, last) in table {
        let instant: @Sendable (Duration) async -> Void = { _ in }
        let r: Rig
        if case .silence = reply { r = rig(resolverForSend(), sleep: instant) } else { r = rig(resolverForSend(), sleep: holdTimeout) }
        r.ax.elements = [el(1, "Send")]
        let runner = r.runner
        let task = Task { await runner.run(goal: goal, mode: .command) }
        if case .say(let words) = reply {
            for _ in 0..<2000 where !runner.isAwaitingAnswer { await Task.yield() }
            #expect(runner.isAwaitingAnswer, "the step was never held")
            #expect(r.statuses.last == "step 1 · say yes to send", "\(goal) / \(words)")
            runner.answer(words)
        } else if case .stop = reply {
            for _ in 0..<2000 where !runner.isAwaitingAnswer { await Task.yield() }
            #expect(runner.isAwaitingAnswer, "the step was never held")
            runner.cancel()
        }
        #expect(await task.value == outcome, "\(goal) / \(reply)")
        #expect(r.input.calls.contains("click:140,55") == clicked, "\(goal) / \(reply)")
        #expect(r.statuses.last == last, "\(goal) / \(reply)")
        #expect(!runner.isAwaitingAnswer)
    }
}

@MainActor @Test func askedQuestionWaitsForTheAnswer() async {
    enum Reply { case say(String), stop, silence }
    let click = Action.click(.label(1), button: .left, count: 1)
    let longQuestion = String(repeating: "q", count: 100)
    let longAnswer = String(repeating: "a", count: 300)
    // (question, what the user does, outcome, the row while waiting, the History record step 2 gets (nil: no step 2))
    let table: [(String, Reply, TaskOutcome, String, String?)] = [
        ("Which game?", .say("the knicks one"), .done("open it"), "step 1 · ? Which game?",
         "Which game?|the knicks one"),
        (longQuestion, .say(longAnswer), .done("open it"), "step 1 · ? " + String(repeating: "q", count: 79) + "…",
         String(repeating: "q", count: 79) + "…|" + String(repeating: "a", count: 200)),
        ("Which game?", .stop, .stopped, "step 1 · ? Which game?", nil),
        ("Which game?", .silence, .stuck("no answer"), "step 1 · ? Which game?", nil),
        ("Which game?", .say("   "), .stuck("no answer"), "step 1 · ? Which game?", nil),
    ]
    for (question, reply, outcome, waiting, record) in table {
        var silent = false
        if case .silence = reply { silent = true }
        // The answer wait's timeout fires at once for a silent user and never otherwise; other sleeps return at once.
        let hold = !silent
        let r = rig(FakeResolver([step(question, .ask), step("open it", .done, [click])]), sleep: { d in
            if d == TaskRunner.answerTimeout, hold { try? await Task.sleep(for: .seconds(30)) }
        })
        r.ax.elements = [el(1, "Watch")]
        let runner = r.runner
        let task = Task { await runner.run(goal: "open the raptors game", mode: .command) }
        if !silent {
            for _ in 0..<2000 where runner.awaitedAnswer != .question { await Task.yield() }
            #expect(runner.awaitedAnswer == .question, "the question never waited")
            #expect(r.statuses.last == waiting)
            #expect(r.input.calls.isEmpty, "nothing runs while it waits")
            switch reply {
            case .say(let words): runner.answer(words)
            default: runner.cancel()
            }
        }
        #expect(await task.value == outcome, "\(reply)")
        #expect(r.resolver.requests.dropFirst().first?.history.first.map { "\($0.intent)|\($0.userAnswer ?? "")" } == record, "\(reply)")
        #expect(r.resolver.requests.dropFirst().first?.history.first?.actions.isEmpty ?? true)
        #expect(r.input.calls.contains("click:140,55") == (record != nil))
        #expect(runner.awaitedAnswer == nil)
    }
}

@MainActor @Test func aFindInATaskPutsTheMatchFirstInTheNextRequestWithoutMovingThePointer() async {
    let r = rig(FakeResolver([step("find it", .continue, [.findOnPage("raptors", movePointer: false)]), step("done", .done)]))
    r.ax.pageMatch = UIElementInfo(id: 1_000_001, frame: CGRect(x: 100, y: 5000, width: 200, height: 20), title: "Raptors vs Celtics", role: "AXLink")
    #expect(await r.runner.run(goal: "open the raptors game", mode: .command) == .done("done"))
    #expect(r.resolver.requests[1].observation.elements.first?.title == "Raptors vs Celtics")
    #expect(r.resolver.requests[1].observation.elements.first?.number == 1)
    #expect(!r.input.calls.contains { $0.hasPrefix("move:") })
}

// MARK: settle by action

@MainActor @Test func settleWaitDependsOnWhatTheStepDid() async {
    // Step 1 runs the actions, step 2 is `done`; the walks and sleeps after the first observation belong to step 1's settle.
    // `changing`: the screen differs for that many walks after step 1 before it holds still.
    let rows: [(String, [Action], changing: Int, sleeps: Int, observations: Int)] = [
        ("typing: one sleep, one look", [.typeText("a"), .wait(ms: 1)], 0, 1, 1),
        ("a wait-only step: no sleep", [.wait(ms: 1)], 0, 0, 1),
        ("typed text ending in a newline submits: polls", [.typeText("cats\n")], 0, 2, 3),
        ("return submits: polls until two readings match", [.pressKey(KeyChord(.return))], 0, 2, 3),
        ("return, page still loading: polls past the floor", [.pressKey(KeyChord(.return))], 2, 3, 4),
    ]
    for (name, actions, changing, sleeps, observations) in rows {
        let counter = SleepCounter()
        let r = rig(FakeResolver([step("act", .continue, actions), step("done", .done)]),
                    sleep: { _ in await counter.tick { _ in } })
        // Walk 0 is the task's first look; the step's settle then sees `changing` new screens, then a repeat.
        if changing > 0 { r.ax.walkLists = (0...(changing + 1)).map { [el(1, "page \($0)")] } }
        #expect(await r.runner.run(goal: "x", mode: .command) == .done("done"), "\(name)")
        #expect(await counter.count == sleeps, "\(name)")
        #expect(r.ax.walks == 1 + observations, "\(name)")
        #expect(r.runner.settleTimes.count == r.runner.stepsRun, "\(name)")
    }
}

@MainActor @Test func aTickingValueStopsTheSettleAtTheSecondPoll() async {
    let counter = SleepCounter()
    let r = rig(FakeResolver([step("submit", .continue, [.pressKey(KeyChord(.return))]), step("done", .done)]),
                sleep: { _ in await counter.tick { _ in } })
    // Every walk shows a new clock value; the page is otherwise the same.
    r.ax.walkLists = (0..<30).map { n in
        [UIElementInfo(id: 1, frame: CGRect(x: 0, y: 40, width: 80, height: 30), title: "clock", role: "AXStaticText", value: "\(n)")]
    }
    #expect(await r.runner.run(goal: "x", mode: .command) == .done("done"))
    #expect(await counter.count == 2)
}

@MainActor @Test func theTypedWindowWaitRunsOnlyWhenNoWindowIsUpYet() async {
    let url = URL(string: "https://example.com")!
    // Settle after step 1: sleeps and snapshots (the first snapshot is the task's own first look).
    let rows: [(String, [Action], window: Bool, wait: HarnessActionResult, waited: Bool, sleeps: Int, snapshots: Int)] = [
        ("open_app, window came: one look", [.openApp("Safari")], false, .delivered(verified: true), true, 0, 2),
        ("open_url, window came: keeps polling", [.openURL(url, app: nil)], false, .delivered(verified: true), true, 2, 4),
        ("open_url, wait timed out: keeps polling", [.openURL(url, app: nil)], false, .failed("wait timed out"), true, 2, 4),
        ("open_app, wait failed: keeps polling", [.openApp("Safari")], false, .notDelivered("no agent"), true, 2, 4),
        ("open_url, a window exists: no wait", [.openURL(url, app: nil)], true, .delivered(verified: true), false, 2, 4),
        ("open_app, a window exists: no wait", [.openApp("Safari")], true, .delivered(verified: true), false, 2, 4),
        ("a click never waits for a window", [.click(.label(1), button: .left, count: 1)], false, .delivered(verified: true), false, 2, 4),
    ]
    for (name, actions, window, result, waited, sleeps, snapshots) in rows {
        let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.waitResult = result
        let counter = SleepCounter()
        let r = harnessRig(FakeResolver([step("act", .continue, actions), step("done", .done)]), harness: h, settleMs: 3000,
                           sleep: { _ in await counter.tick { _ in } })
        r.ax.apps = ["Safari"]
        r.ax.windowFrame = window ? CGRect(x: 0, y: 0, width: 400, height: 300) : nil
        #expect(await r.runner.run(goal: "x", mode: .command) == .done("done"), "\(name)")
        let waits = h.calls.filter { $0.hasPrefix("act:wait") }
        #expect(waits == (waited ? ["act:wait --event window-opened --app Safari --timeout 1500"] : []), "\(name)")
        #expect(await counter.count == sleeps, "\(name)")
        #expect(h.calls.filter { $0.hasPrefix("snapshot:") }.count == snapshots, "\(name)")
    }
}

@MainActor @Test func timeSpentInTheWindowWaitCountsTowardSettleMs() async {
    let clock = FakeClock()
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]; h.waitResult = .failed("wait timed out")
    h.onWait = { clock.advance(.milliseconds(2800)) }
    let sleeps = SleepRecorder()
    let r = harnessRig(FakeResolver([step("open", .continue, [.openApp("Safari")]), step("done", .done)]), harness: h,
                       settleMs: 3000, clock: clock, sleep: { await sleeps.add($0) })
    r.ax.apps = ["Safari"]; r.ax.windowFrame = nil
    #expect(await r.runner.run(goal: "x", mode: .command) == .done("done"))
    #expect(await sleeps.all == [.milliseconds(200)])   // 3000 ms limit - 2800 ms waited: one short poll, then stop
}

@MainActor @Test func aStopDuringTheWindowWaitEndsTheTask() async {
    let h = FakeHarness(); h.snapshotResults = [harnessSnapshot()]
    h.waitResult = .delivered(verified: true); h.waitDelay = .seconds(30)
    let r = harnessRig(FakeResolver([step("open", .continue, [.openApp("Safari")]), step("done", .done)]), harness: h, settleMs: 3000)
    r.ax.apps = ["Safari"]; r.ax.windowFrame = nil
    let runner = r.runner
    let started = ContinuousClock.now
    let task = Task { await runner.run(goal: "x", mode: .command) }
    while !h.recordedCalls.contains(where: { $0.hasPrefix("act:wait") }), started.duration(to: .now) < .seconds(5) {
        try? await Task.sleep(for: .milliseconds(10))
    }
    runner.cancel()
    #expect(await task.value == .stopped)
    #expect(started.duration(to: .now) < .seconds(10))
}

private actor SleepRecorder {
    var all: [Duration] = []
    func add(_ d: Duration) { all.append(d) }
}

@MainActor @Test func followUpSeesTheEarlierTaskAndLastTaskTracksTheOutcome() async {
    let click = Action.click(.cursor, button: .left, count: 1)
    let earlier = EarlierTask(goal: "play the latest video", history: [StepRecord(intent: "open channel", actions: [click])], result: "done: playing")
    let r = rig(FakeResolver([step("open it", .continue, [click]), step("playing", .done, [click])]))
    r.resolver.planResult = .success(TaskPlan(steps: [PlanStep(intent: "x", kind: .waitForMedia, check: PlanCheck(kind: .mediaPlaying, text: ""))]))
    _ = await r.runner.run(goal: "no, the other one on youtube please", mode: .command, earlier: earlier)
    // Every request carries it, a follow-up is never planned, and the kept goal chains the two requests.
    #expect(r.resolver.requests.count == 2 && r.resolver.requests.allSatisfy { $0.earlier == earlier })
    #expect(r.resolver.planGoals.isEmpty)
    #expect(r.runner.lastTask?.goal == "play the latest video; then: no, the other one on youtube please")
    #expect(r.runner.lastTask?.result == "done: playing" && r.runner.lastTask?.history.count == 2 && r.runner.lastTask?.history.last?.intent == "playing")
    // (steps, stop mid-task, expected `lastTask?.result`): kept after done, stuck and stop; cleared after ignore and failure.
    let table: [(Result<IntentStep, IntentError>, Bool, String?)] = [
        (.success(step("ok", .done)), false, "done: ok"), (.success(step("hmm", .stuck)), false, "stuck: hmm"),
        (.success(step("go", .continue, [click])), true, "stopped"),
        (.success(step("nah", .ignore)), false, nil), (.failure(.timeout), false, nil),
    ]
    let runner = r.runner
    for (result, stop, kept) in table {
        r.resolver.steps = [result]; r.resolver.requests = []
        if stop { r.resolver.onResolve = { @Sendable _ in await runner.cancel() } } else { r.resolver.onResolve = nil }
        _ = await r.runner.run(goal: "do it", mode: .command)
        #expect(r.runner.lastTask?.result == kept, "\(result)")
    }
}
