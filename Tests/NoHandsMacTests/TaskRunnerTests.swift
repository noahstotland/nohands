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
