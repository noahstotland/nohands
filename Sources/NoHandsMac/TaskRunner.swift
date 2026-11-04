import Foundation
import NoHandsCore

public enum TaskOutcome: Equatable, Sendable {
    case done(String)
    case stuck(String)
    case ignored
    case stopped
    /// The resolver failed; the message is the HUD text.
    case failed(String)
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
    private let sleep: @Sendable (Duration) async -> Void

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
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.config = config
        self.resolver = resolver
        self.executor = executor
        self.observer = observer
        self.overlay = overlay
        self.sleep = sleep
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
        // Settle first too: Chromium exposes its page tree shortly after AXManualAccessibility is set.
        var settleStart = ContinuousClock.now
        var (observation, labels) = await settle(mode: mode)
        var settled = settleStart.duration(to: .now)

        for n in 1...maxSteps {
            if isCancelled { return finish(.stopped) }
            let request = StepRequest(goal: goal, step: n, maxSteps: maxSteps, history: history, observation: observation)
            let step: IntentStep
            switch await resolveCancellable(request) {
            case .step(let s): step = s
            case .end(let outcome): return finish(isCancelled ? .stopped : outcome)
            }
            switch step.status {
            case .ignore: return finish(.ignored)
            case .stuck: return finish(.stuck(step.intent))
            case .continue, .done:
                if repeats.record(step.actions) { return finish(.stuck(Self.repeating)) }
            }

            if isCancelled { return finish(.stopped) }
            overlay.showHUD("step \(n) · \(step.intent)", duration: .seconds(4))
            let failure = await executeCancellable(step.actions, labels: labels)
            stepsRun = n
            onStep?(n, step, settled, failure)
            if isCancelled { return finish(.stopped) }
            // A `done` whose actions failed did not achieve the goal: record the failure and let the model react
            // (repeat detection above covers both `continue` and `done`, so a stubborn failing batch ends as stuck).
            if step.status == .done && failure == nil { return finish(.done(step.intent)) }
            history.append(StepRecord(intent: step.intent, actions: step.actions, failure: failure))
            if n < maxSteps {
                settleStart = ContinuousClock.now
                (observation, labels) = await settle(mode: mode)
                settled = settleStart.duration(to: .now)
            }
        }
        return finish(.stuck(Self.stepLimit))
    }

    /// Observes until two consecutive observations are the same (after at least 300 ms), or `settleMs` elapses.
    /// Time is counted from the injected sleeps so tests run instantly. `settleMs == 0` observes once.
    func settle(mode: Mode) async -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) {
        var current = observer.observe(mode: mode, overlay: overlay.state)
        let limit = max(0, config.settleMs)
        var elapsed = 0
        while elapsed < limit, !isCancelled {
            let step = min(Self.pollInterval, limit - elapsed)
            await sleep(.milliseconds(step))
            elapsed += step
            let next = observer.observe(mode: mode, overlay: overlay.state)
            let same = Settle.same(current.observation, next.observation)
            current = next
            if same && elapsed >= Self.minSettleMs { break }
        }
        return current
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

    private func finish(_ outcome: TaskOutcome) -> TaskOutcome {
        // Spec Safety: a held mouse button is released on any exit; a successful `done` keeps what it did.
        if case .done = outcome {} else { executor.releaseAll() }
        overlay.showHUD(PipelineText.hud(for: outcome))
        return outcome
    }
}
