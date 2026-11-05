import Foundation
import NoHandsCore

public enum TaskOutcome: Equatable, Sendable {
    case done(String)
    case stuck(String)
    case ignored
    case stopped
    /// The resolver failed; the message is the HUD text.
    case failed(String)

    /// Exit status for `nohands-cli task`: 0 for done (and ignored), 2 for stuck, failed or stopped.
    public var exitStatus: Int32 {
        switch self {
        case .done, .ignored: 0
        case .stuck, .failed, .stopped: 2
        }
    }
}

/// Drives one spoken goal to completion: observe → resolve one step → act → settle → repeat.
/// Guards: step cap (`maxTaskSteps`), repeat detection, `cancel()`.
@MainActor public final class TaskRunner {
    static let stepLimit = "step limit reached"
    static let repeating = "repeating the same action"
    static let pollInterval = 250
    static let minSettleMs = 300

    private let config: AppConfig
    private let resolver: any IntentResolving
    private let executor: ActionExecutor
    private let observer: ScreenObserver
    private let overlay: any OverlayPresenting
    /// agent-desktop, when installed and chosen. The task's harness kind is decided by the first observation.
    private let harness: (any DesktopHarness)?
    private var taskHarness: HarnessKind = .native
    private var sessionID: String?
    private let sleep: @Sendable (Duration) async -> Void
    /// Measures observation time (injected so tests are deterministic).
    private let now: @Sendable () -> ContinuousClock.Instant

    private var cancelled = false
    /// Steps whose actions were executed in the current (or last) `run`.
    public private(set) var stepsRun = 0
    /// The in-flight resolve or execute; `cancel()` cancels it so an HTTP request or `wait` aborts.
    private var inFlight: Task<Void, Never>?
    /// Diagnostics hook (the CLI prints steps with it; the app leaves it nil). Called after each executed step with
    /// the step number, the step, how long the settle before it took, and the executor's failure (nil on success).
    public var onStep: ((_ n: Int, _ step: IntentStep, _ settle: Duration, _ failure: String?) -> Void)?

    public init(config: AppConfig, resolver: any IntentResolving, executor: ActionExecutor,
                observer: ScreenObserver, overlay: any OverlayPresenting,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
                harness: (any DesktopHarness)? = nil) {
        self.config = config
        self.harness = harness
        self.resolver = resolver
        self.executor = executor
        self.observer = observer
        self.overlay = overlay
        self.sleep = sleep
        self.now = now
    }

    /// Stops the running task at the next check (before a resolve or execute) and aborts the in-flight one.
    public func cancel() {
        cancelled = true
        inFlight?.cancel()
    }

    private var isCancelled: Bool { cancelled || Task.isCancelled }

    public func run(goal: String, mode: Mode) async -> TaskOutcome {
        cancelled = false
        stepsRun = 0
        let maxSteps = max(1, config.maxTaskSteps)
        var history: [StepRecord] = []
        var repeats = RepeatDetector(limit: 3)
        // Observe once. Settle first only when that walk just exposed a Chromium page tree (it fills in ~0.5 s
        // later); otherwise the screen is already what the user sees and the model is asked at once.
        _ = observer.didJustExpose()   // clear a flag left over from a walk after the previous task's last step
        _ = executor.takeReadings()
        // The first observation decides the task's harness: agent-desktop when it could read the frontmost app,
        // else native for the whole task (the prompt and the local model's cached prefix must not flip mid-task).
        taskHarness = harness == nil ? .native : .agentDesktop
        if taskHarness == .agentDesktop, config.agentDesktopTrace, let harness {
            sessionID = await harness.startSession(name: "nohands-\(Int(Date().timeIntervalSince1970))")
        }
        var settleStart = ContinuousClock.now
        var first = await observeTimed(mode: mode)
        if taskHarness == .agentDesktop, !first.fromHarness {
            taskHarness = .native
            first.result.observation.harness = .native
        }
        if observer.didJustExpose() { first = (await settle(mode: mode, from: first), first.ms, first.fromHarness) }
        var (observation, labels) = first.result
        var settled = settleStart.duration(to: .now)

        for n in 1...maxSteps {
            if isCancelled { return await finish(.stopped) }
            let request = StepRequest(goal: goal, step: n, maxSteps: maxSteps, history: history, observation: observation)
            let step: IntentStep
            switch await resolveCancellable(request) {
            case .step(let s): step = s
            case .end(let outcome): return await finish(isCancelled ? .stopped : outcome)
            }
            switch step.status {
            // An `ignore` after earlier steps already acted is the model giving up mid-task, not chatter.
            case .ignore: return await finish(.ignored, hud: n > 1 ? Self.stoppedHUD(step.intent) : nil)
            case .stuck: return await finish(.stuck(step.intent))
            case .continue, .done:
                if repeats.record(step.actions) { return await finish(.stuck(Self.repeating)) }
            }

            if isCancelled { return await finish(.stopped) }
            overlay.showHUD("step \(n) · \(step.intent)", duration: .seconds(4))
            // Code-level guard: never close a tab/window or quit an app the goal did not ask to close or quit.
            // A blocked step runs nothing and is recorded as a failed step so the model can react.
            let failure: String?
            if let blocked = ShortcutGuard.blocked(step.actions, goal: goal) { failure = blocked }
            else {
                let shown = overlay.state
                failure = await executeCancellable(step.actions, labels: labels)
                // Badges or a grid are only valid for the screen they were drawn on: once a step has acted, hide
                // them so the next observation walks the screen afresh (a `.label` click leaves them up, and the
                // badge map would otherwise be reused). One this step just drew (e.g. "show numbers") stays, and a step
                // with no actions changed nothing.
                if !step.actions.isEmpty && shown != .none && overlay.state == shown { overlay.hide() }
            }
            stepsRun = n
            onStep?(n, step, settled, failure)
            if isCancelled { return await finish(.stopped) }
            // A `done` whose actions failed did not achieve the goal: record the failure and let the model react
            // (repeat detection above covers both `continue` and `done`, so a stubborn failing batch ends as stuck).
            let readings = executor.takeReadings()
            if step.status == .done && failure == nil {
                return await finish(.done(step.intent), hud: readings.first.map { "\(step.intent) — \($0.prefix(80))" })
            }
            history.append(StepRecord(intent: step.intent, actions: step.actions, failure: failure))
            if n < maxSteps {
                settleStart = ContinuousClock.now
                (observation, labels) = await settle(mode: mode, readings: readings)
                settled = settleStart.duration(to: .now)
            }
        }
        return await finish(.stuck(Self.stepLimit))
    }

    typealias Observed = (observation: ScreenObservation, labels: [Int: UIElementInfo])

    /// Observes until two consecutive observations are the same (after at least 300 ms), or `settleMs` elapses.
    /// Elapsed time is the injected sleeps plus the measured wall time of each observation, so production is
    /// bounded by `settleMs` in wall time while tests with instant fakes run instantly. `settleMs == 0` observes
    /// once. `first` is an observation just taken (counted from its own duration) instead of a fresh one.
    func settle(mode: Mode, from first: (result: Observed, ms: Int, fromHarness: Bool)? = nil, readings: [String] = []) async -> Observed {
        var taken: (result: Observed, ms: Int, fromHarness: Bool)
        if let first { taken = first } else { taken = await observeTimed(mode: mode, readings: readings) }
        var current = taken.result
        let limit = max(0, config.settleMs)
        var elapsed = taken.ms
        while elapsed < limit, !isCancelled {
            let step = min(Self.pollInterval, limit - elapsed)
            await sleep(.milliseconds(step))
            elapsed += step
            let next = await observeTimed(mode: mode, readings: readings)
            elapsed += next.ms
            let same = Settle.same(current.observation, next.result.observation)
            current = next.result
            if same && elapsed >= Self.minSettleMs { break }
        }
        return current
    }

    /// One observation, run off the main actor (an AX walk can take up to its budget, ~1-2 s on a busy page),
    /// and how long it took in milliseconds. The overlay state and screen rects are read here, on the main actor.
    private func observeTimed(mode: Mode, readings: [String] = []) async -> (result: Observed, ms: Int, fromHarness: Bool) {
        let observer = self.observer
        let state = overlay.state
        let screens = observer.screenRects()
        let kind = taskHarness
        let start = now()
        let r = await Task.detached {
            await observer.observe(mode: mode, overlay: state, screens: screens, harnessKind: kind, readings: readings)
        }.value
        return ((r.observation, r.labels), Int(start.duration(to: now()) / .milliseconds(1)), r.fromHarness)
    }

    private enum Resolved { case step(IntentStep), end(TaskOutcome) }

    private func resolveCancellable(_ request: StepRequest) async -> Resolved {
        let resolver = self.resolver
        var result: Resolved = .end(.stopped)
        await runCancellable {
            do {
                result = .step(try await resolver.resolve(request))
            } catch let error as IntentError {
                if case .cancelled = error { result = .end(.stopped) }
                else { result = .end(.failed(PipelineText.hud(for: error) ?? "error")) }
            } catch is CancellationError {
                result = .end(.stopped)
            } catch {
                result = .end(.failed("error"))
            }
        }
        return result
    }

    private func executeCancellable(_ actions: [Action], labels: [Int: UIElementInfo]) async -> String? {
        let executor = self.executor
        var failure: String?
        await runCancellable { failure = await executor.execute(actions, labels: labels) }
        return failure
    }

    /// Runs `body` in a child task that `cancel()` (or cancelling the caller) cancels.
    private func runCancellable(_ body: @escaping @MainActor () async -> Void) async {
        let task = Task { @MainActor in await body() }
        inFlight = task
        defer { inFlight = nil }
        if cancelled { task.cancel() }
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    static func stoppedHUD(_ intent: String) -> String { intent.isEmpty ? PipelineText.stopped : "stopped: \(intent)" }

    /// `hud` overrides the outcome's usual finish HUD.
    private func finish(_ outcome: TaskOutcome, hud: String? = nil) async -> TaskOutcome {
        // Spec Safety: a held mouse button is released on any exit; a successful `done` keeps what it did.
        if case .done = outcome {} else { executor.releaseAll() }
        overlay.showHUD(hud ?? PipelineText.hud(for: outcome))
        // The HUD is already up; ending the traced session is quick bookkeeping.
        if let id = sessionID, let harness {
            sessionID = nil
            await harness.endSession(id)
        }
        return outcome
    }
}
