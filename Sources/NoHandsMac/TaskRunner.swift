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
    static let notPlaying = "not playing yet"
    static let pollInterval = 250
    static let minSettleMs = 300
    /// The most a wait for a new window may take. The event can miss a window that appears before the wait starts,
    /// so the rest of `settleMs` is polled instead of spent waiting.
    static let windowWaitMs = 1500
    /// How long a capture may take before the step goes on without a picture.
    static let captureDeadline: Duration = .seconds(2)
    static let looking = "looking at the screen"
    /// How long a step held for a spoken yes waits for the answer before the task stops.
    nonisolated static let answerTimeout: Duration = .seconds(30)

    private let config: AppConfig
    private let resolver: any IntentResolving
    private let executor: ActionExecutor
    private let observer: ScreenObserver
    private let overlay: any OverlayPresenting
    /// Takes the vision fallback's picture; nil (flag off, local backend) means no step ever gets one.
    private let screenshots: (any ScreenshotProviding)?
    /// Test hook: shortens the capture deadline.
    var captureDeadline = TaskRunner.captureDeadline
    /// The capture being waited for, if any. `cancel()` resumes it so a hung capture cannot hold up a stop.
    private var captureWait: CheckedContinuation<ScreenshotResult, Never>?
    /// Identifies the current wait, so a capture or deadline that finishes late cannot resume a newer one.
    private var captureWaitID = 0
    /// The task paused for a spoken answer, if any. `answer(_:)` resumes it with the words, `cancel()` and the
    /// timeout with nil. The caller decides what counts as yes.
    private var answerWait: CheckedContinuation<String?, Never>?
    /// Identifies the current answer wait, so a timeout that fires late cannot resume a newer one.
    private var answerWaitID = 0
    /// agent-desktop, when installed and chosen. The task's harness kind is decided by the first observation.
    private let harness: (any DesktopHarness)?
    private var taskHarness: HarnessKind = .native
    private var sessionID: String?
    /// Overlays (sheet, menu, …) the last step's actions left open, read from the harness once per settle so every
    /// poll of that settle observes the same surface (reading clears the harness's copy).
    private var pendingSurfaces: [String] = []
    private let sleep: @Sendable (Duration) async -> Void
    /// Measures observation time (injected so tests are deterministic).
    private let now: @Sendable () -> ContinuousClock.Instant

    /// Which browser tabs and windows are the user's and which the task opened; one per task.
    private var ledger = TabLedger()
    /// Set after a step that navigated: the next browser observation's active tab is the task's.
    private var markTaskTab = false
    /// True until the task's first observation has been annotated.
    private var atTaskStart = true
    /// Set by `cancel()`, cleared when a run starts. Readable so tests can tell which runner a stop reached.
    private(set) var cancelled = false
    /// While a plan runs, the element cap for each observation (the model is not sent those lists); nil otherwise.
    private var planLimit: Int?
    /// Steps whose actions were executed in the current (or last) `run`.
    public private(set) var stepsRun = 0
    /// Each step's settle wait in ms, in the order `onStep` reported them, for the current (or last) `run`.
    public private(set) var settleTimes: [Int] = []
    /// The in-flight resolve or execute; `cancel()` cancels it so an HTTP request or `wait` aborts.
    private var inFlight: Task<Void, Never>?
    /// Diagnostics hook (the CLI prints steps with it; the app leaves it nil). Called after each executed step with
    /// the step number, the step, how long the settle before it took, and the executor's failure (nil on success).
    public var onStep: ((_ n: Int, _ step: IntentStep, _ settle: Duration, _ failure: String?) -> Void)?
    /// The prompt's status as the task goes: each step as it starts, a step's failure, and the finish line. The
    /// pipeline puts it on the prompt's row; the CLI prints it.
    public var onStatus: ((PromptStatus) -> Void)?
    /// The steps so far as data, for the corner panel: emitted when the run starts (empty), when a step starts, when
    /// it ends and when the run ends stuck. The CLI leaves it nil.
    public var onTrail: ((TaskTrail) -> Void)?
    private var trail = TaskTrail(maxSteps: 1)

    public init(config: AppConfig, resolver: any IntentResolving, executor: ActionExecutor,
                observer: ScreenObserver, overlay: any OverlayPresenting,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
                now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
                harness: (any DesktopHarness)? = nil,
                screenshots: (any ScreenshotProviding)? = nil) {
        self.config = config
        self.screenshots = config.visionEnabled ? screenshots : nil
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
        endCaptureWait(with: .failed)
        endAnswerWait(with: nil)
    }

    /// True while the task is paused for a spoken answer: the pipeline then sends the user's next words to `answer`.
    public var isAwaitingAnswer: Bool { answerWait != nil }

    /// Hands the paused task the user's reply. Does nothing when no answer is awaited.
    public func answer(_ transcript: String) { endAnswerWait(with: transcript) }

    private var isCancelled: Bool { cancelled || Task.isCancelled }

    public func run(goal: String, mode: Mode) async -> TaskOutcome {
        cancelled = false
        planLimit = nil
        stepsRun = 0
        settleTimes = []
        // A goal about playing media gets a longer budget: stream sites throw overlays and pop-unders first.
        let maxSteps = max(1, MediaGoal.matches(goal) ? config.maxMediaTaskSteps : config.maxTaskSteps)
        trail = TaskTrail(maxSteps: maxSteps)
        setPhase(.reading)   // before the first screen read, which can take a second or two
        ledger = TabLedger()
        markTaskTab = false
        atTaskStart = true
        observer.resetBrowserTokens()
        var history: [StepRecord] = []
        var repeats = RepeatDetector(limit: 3)
        var askedAgainForMedia = false
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
        pendingSurfaces = harness?.takeOpenSurfaces() ?? []
        var first = await observeTimed(mode: mode)
        if taskHarness == .agentDesktop, !first.fromHarness {
            taskHarness = .native
            first.result.observation.harness = .native
        }
        if observer.didJustExpose() { first = (await settle(mode: mode, from: first), first.ms, first.fromHarness) }
        var (observation, labels) = first.result
        await annotateTabs(&observation)
        var settled = settleStart.duration(to: .now)

        // A goal that looks multi-step may get a plan the model writes once; code then runs and checks it, and the
        // loop below takes over on any miss. Every step still goes through the guards below.
        var engine: PlanEngine?
        if PlanGate.mayPlan(goal: goal) {
            setPhase(.planning)
            if let plan = await askForPlan(goal) {
                engine = PlanEngine(plan: plan)
                planLimit = TaskPlan.observedElements
            }
            if isCancelled { return await finish(.stopped) }
        }

        for n in 1...maxSteps {
            if isCancelled { return await finish(.stopped) }
            var planned: IntentStep?
            if engine != nil {
                // A failed step (the executor, a guard, "not playing yet") ends the plan; the model sees that failure.
                if history.last?.failure == nil {
                    switch engine!.next(observation, frames: labels.mapValues(\.frame)) {
                    case .step(let s): planned = s
                    case .finish(let line): planned = IntentStep(intent: line, status: .done, actions: [])
                    case .handOver(let reason):
                        if let last = history.indices.last { history[last].failure = reason }
                    }
                }
                if planned == nil {
                    engine = nil
                    endPlan(&observation, &labels)
                }
            }
            var request = StepRequest(goal: goal, step: n, maxSteps: maxSteps, history: history, observation: observation)
            var step: IntentStep
            if let planned {
                step = planned
            } else {
                // A picture of the focused window, only where the accessibility tree has just failed the model.
                if screenshots != nil,
                   VisionTrigger.wantsPicture(lastFailure: history.last?.failure, lastActions: history.last?.actions ?? []) {
                    request.vision = await pictureInput(for: observation, step: n)
                    if isCancelled { return await finish(.stopped) }
                }
                while true {
                    setPhase(.thinking)
                    switch await resolveCancellable(request) {
                    case .step(let s): step = s
                    case .end(let outcome): return await finish(isCancelled ? .stopped : outcome)
                    }
                    // Stuck without a picture: look once and ask again at the same step (nothing ran, so no step is used).
                    guard step.status == .stuck, request.vision == nil, screenshots != nil, observation.surface == nil else { break }
                    let picture = await pictureInput(for: observation, step: n)
                    if isCancelled { return await finish(.stopped) }
                    if case .unavailable(let why) = picture { return await finish(.stuck("\(step.intent) (\(why))")) }
                    request.vision = picture
                }
            }
            // A typed web address is opened instead, before anything records the step: History, repeat detection and
            // the task-tab mark all see the `open_url` that runs.
            step.actions = TypedAddressGuard.rewrite(step.actions, goal: goal)
            switch step.status {
            // An `ignore` after earlier steps already acted is the model giving up mid-task, not chatter.
            case .ignore: return await finish(.ignored, hud: n > 1 ? Self.stoppedHUD(step.intent) : nil)
            case .stuck: return await finish(.stuck(step.intent))
            case .continue, .done:
                if repeats.record(step.actions) { return await finish(.stuck(Self.repeating)) }
            }

            if isCancelled { return await finish(.stopped) }
            onStatus?(.running("step \(n) · \(step.intent)"))
            trail.begin(number: n, intent: step.intent, actions: step.actions)
            trail.phase = .acting
            onTrail?(trail)
            // Code-level guard: never close a tab/window or quit an app the goal did not ask to close or quit.
            // A blocked step runs nothing and is recorded as a failed step so the model can react.
            // On a step that carried a picture, a point is in the picture's pixels: map it to the screen, and run
            // nothing if it is outside the picture or the photographed window has since moved.
            // A click by name is pointed at the element list the model read (list-dependent, so not in History).
            var actions = ElementNames.bind(step.actions, labels: labels, menuBarTitles: observation.menuBarTitles, goal: goal)
            var pointFailure: String?
            if case .image(let shot)? = request.vision, ScreenshotGeometry.holdsPoint(actions) {
                switch ScreenshotGeometry.mapPoints(actions, shot: shot) {
                case .refused(let why): pointFailure = why
                case .mapped(let mapped):
                    let front = observer.frontWindow()
                    if front.app == shot.app, let frame = front.frame, ScreenshotGeometry.sameFrame(frame, shot.windowFrame) {
                        actions = mapped
                    } else {
                        pointFailure = ActionExecutor.elementChanged
                    }
                }
            }
            // With vision on, a point is only ever in a picture's pixels: on a step without one (a repeat from history,
            // or text in an earlier picture) it would be read as a raw screen point and could land in another app.
            if pointFailure == nil, screenshots != nil, ScreenshotGeometry.holdsPoint(actions), !hasImage(request.vision) {
                pointFailure = ScreenshotGeometry.needsPictureReason
            }
            let failure: String?
            if let pointFailure { failure = pointFailure }
            else if let blocked = ShortcutGuard.blocked(actions, goal: goal)
                ?? TabGuard.blocked(actions, listing: observation.tabs, goal: goal)
                ?? MenuBarGuard.blocked(actions, labels: labels, menuBarTitles: observation.menuBarTitles, goal: goal,
                                        badgesShowing: observation.overlay == "labels") { failure = blocked }
            else {
                // An irreversible button the request did not name waits for a spoken yes; anything else, silence or
                // a stop ends the task before the step runs.
                if let verb = IrreversibleGuard.held(actions, labels: labels, goal: goal) {
                    onStatus?(.running("step \(n) · say yes to \(verb)"))
                    let reply = await awaitAnswer(timeout: Self.answerTimeout)
                    if isCancelled { return await finish(.stopped) }
                    guard let reply, ConfirmAnswer.isYes(reply, attention: config.attentionGate) else {
                        return await finish(.stopped, hud: "stopped: \(verb) not confirmed")
                    }
                    onStatus?(.running("step \(n) · \(step.intent)"))
                }
                let shown = overlay.state
                failure = await executeCancellable(actions, labels: labels, tabs: observation.tabs)
                // Only a step that ran clean left the task's page in front; a failed one may not have navigated.
                if failure == nil, step.actions.contains(where: Self.navigates) { markTaskTab = true }
                // Badges or a grid are only valid for the screen they were drawn on: once a step has acted, hide
                // them so the next observation walks the screen afresh (a `.label` click leaves them up, and the
                // badge map would otherwise be reused). One this step just drew (e.g. "show numbers") stays, and a step
                // with no actions (or only `look`) changed nothing.
                if !step.actions.isEmpty && !step.actions.allSatisfy({ $0 == .look }) && shown != .none && overlay.state == shown { overlay.hide() }
            }
            stepsRun = n
            // A step cut short by stop stays running, so the panel shows it as stopped, not failed.
            if failure != ActionExecutor.cancelled {
                trail.end(number: n, failure: failure)
                trail.phase = .reading   // the settle and the next look at the screen
                onTrail?(trail)
            }
            settleTimes.append(Int(settled / .milliseconds(1)))
            onStep?(n, step, settled, failure)
            if let failure, failure != ActionExecutor.cancelled { onStatus?(.running("step \(n) · \(step.intent) ✗ \(failure)")) }
            if isCancelled { return await finish(.stopped) }
            // A `done` whose actions failed did not achieve the goal: record the failure and let the model react
            // (repeat detection above covers both `continue` and `done`, so a stubborn failing batch ends as stuck).
            let readings = executor.takeReadings()
            if step.status == .done && failure == nil {
                let finished = TaskOutcome.done(step.intent)
                let hud = readings.first.map { "\(step.intent) — \($0.prefix(80))" }
                guard MediaSignal.wantsPlayback(goal: goal) else { return await finish(finished, hud: hud) }
                // A goal to play something is done when it plays, not when the page loaded: look once more at the
                // screen after this step's actions. A visible Play button sends the model round once more.
                settleStart = ContinuousClock.now
                pendingSurfaces = harness?.takeOpenSurfaces() ?? []
                (observation, labels) = await settle(mode: mode, readings: readings)
                settled = settleStart.duration(to: .now)
                if isCancelled { return await finish(.stopped) }
                guard observation.media == .paused else { return await finish(finished, hud: hud) }
                if askedAgainForMedia || n == maxSteps { return await finish(.stuck(Self.notPlaying)) }
                askedAgainForMedia = true
                history.append(StepRecord(intent: step.intent, actions: step.actions, failure: Self.notPlaying))
                continue
            }
            history.append(StepRecord(intent: step.intent, actions: step.actions, failure: failure))
            if n < maxSteps {
                settleStart = ContinuousClock.now
                pendingSurfaces = harness?.takeOpenSurfaces() ?? []
                (observation, labels) = await settle(mode: mode, readings: readings, after: step.actions)
                if !isCancelled { await annotateTabs(&observation) }
                settled = settleStart.duration(to: .now)
            }
        }
        return await finish(.stuck(Self.stepLimit))
    }

    /// Asks the resolver for a plan and keeps it only if it passes `TaskPlan.validated`. Any error, including an
    /// outage, means no plan: the loop's first call then reports a real outage. A cancel is seen by the caller.
    private func askForPlan(_ goal: String) async -> TaskPlan? {
        let resolver = self.resolver
        var plan: TaskPlan?
        await runCancellable { plan = (try? await resolver.plan(goal: goal)) ?? nil }
        return isCancelled ? nil : plan?.validated(goal: goal)
    }

    /// The plan is over: reads go back to the normal cap, and the observation the model is about to see is cut to it.
    private func endPlan(_ observation: inout ScreenObservation, _ labels: inout [Int: UIElementInfo]) {
        planLimit = nil
        let cap = observer.elementCap
        guard observation.elements.count > cap else { return }
        observation.elements = Array(observation.elements.prefix(cap))
        let kept = Set(observation.elements.map(\.number))
        labels = labels.filter { kept.contains($0.key) }
    }

    /// Steps that open or load a page in the browser: the tab they leave in front is the task's.
    nonisolated private static func navigates(_ action: Action) -> Bool {
        switch action {
        case .openURL, .search, .searchSite: true
        default: false
        }
    }

    /// Turns the browser windows the observer read into the numbered `Tabs:` list. The first time a browser is seen
    /// in front its tabs become the user's; a window-less browser (a cold launch) waits for its first window.
    ///
    /// A browser first seen late (not in front at the task's first observation) may still be listing its windows and
    /// tabs one at a time, as a cold launch or session restore does. It is read once more after a short pause and
    /// the union of the two reads is the baseline; no step runs in between, so nothing the task opened is in it.
    private func annotateTabs(_ observation: inout ScreenObservation) async {
        // Only the task's first observation shows the browser the user had in front; any other is a late arrival.
        let atStart = atTaskStart
        atTaskStart = false
        // The task's tab is marked at the first observation after the navigation; if that is not a browser, the page
        // went elsewhere and a later browser's front tab is not the task's.
        guard var windows = observation.browserWindows else { observation.tabs = nil; markTaskTab = false; return }
        guard !windows.isEmpty else { observation.tabs = nil; return }
        // Keyed on the app the windows were read from, not the one named at the start of the observation.
        let app = observation.browserApp ?? observation.app
        var seenFirst: [BrowserWindow] = []
        if !atStart, !ledger.hasBaseline(app: app) {
            await sleep(Self.lateBrowserPause)
            let observer = self.observer
            let read = await Task.detached { () -> (app: String, windows: [BrowserWindow])? in observer.browserWindows() }.value
            if let again = read, again.app == app, !again.windows.isEmpty {
                seenFirst = windows
                windows = again.windows
            }
        }
        ledger.baseline(app: app, windows: windows, alsoSeen: seenFirst)
        if markTaskTab { ledger.markTaskTab(app: app, windows: windows); markTaskTab = false }
        observation.tabs = ledger.listing(app: app, windows: windows)
    }

    /// The pause before the second read of a browser first seen late.
    private static let lateBrowserPause: Duration = .milliseconds(300)

    typealias Observed = (observation: ScreenObservation, labels: [Int: UIElementInfo])

    /// Waits for the screen after a step, as long as what the step did calls for (`SettlePolicy`), never longer than
    /// `settleMs` of wall time. `none` observes once, `oneLook` sleeps 300 ms and observes once, and `full` observes
    /// until two consecutive observations are the same (after at least 300 ms) or a value that keeps ticking is the
    /// only difference. Elapsed time is the injected sleeps plus the measured wall time of each observation, so
    /// tests with instant fakes run instantly. `settleMs == 0` observes once with no sleep, for every policy.
    /// `actions` is the step just run; nil (the first step's Chromium exposure, the playback check) polls as `full`.
    /// `first` is an observation just taken (counted from its own duration) instead of a fresh one.
    func settle(mode: Mode, from first: (result: Observed, ms: Int, fromHarness: Bool)? = nil, readings: [String] = [],
                after actions: [Action]? = nil) async -> Observed {
        let limit = max(0, config.settleMs)
        let policy = actions.map(SettlePolicy.for) ?? .full
        if limit == 0 || policy == .none {
            if let first { return first.result }
            return await observeTimed(mode: mode, readings: readings).result
        }
        if policy == .oneLook {
            await sleep(.milliseconds(min(Self.minSettleMs, limit)))
            return await observeTimed(mode: mode, readings: readings).result
        }
        var elapsed = 0
        var windowWait: WindowWait?
        if first == nil, let actions, let wait = await waitForNewWindow(after: actions, limit: limit) {
            windowWait = wait
            elapsed = wait.ms
            // A stop during the wait: the caller ends the task, so skip the observation nobody will read.
            if isCancelled { return (ScreenObservation(app: "", mode: mode), [:]) }
        }
        let taken: (result: Observed, ms: Int, fromHarness: Bool)
        if let first { taken = first } else { taken = await observeTimed(mode: mode, readings: readings) }
        elapsed += taken.ms
        var current = taken.result
        if let windowWait, windowWait.delivered, windowWait.appOnly { return current }
        var watch = SettleWatch()
        _ = watch.feed(current.observation)
        while elapsed < limit, !isCancelled {
            let step = min(Self.pollInterval, limit - elapsed)
            await sleep(.milliseconds(step))
            elapsed += step
            let next = await observeTimed(mode: mode, readings: readings)
            elapsed += next.ms
            current = next.result
            if watch.feed(current.observation) && elapsed >= Self.minSettleMs { break }
        }
        return current
    }

    private struct WindowWait { var delivered: Bool; var appOnly: Bool; var ms: Int }

    /// After a step that opened a URL or an app, with agent-desktop and no window in the front app yet: blocks until
    /// agent-desktop sees a window open, for at most `limit` ms (the wait counts against `settleMs`). Nil when there
    /// is nothing to wait for, in which case the step just polls. A failed or timed-out wait never fails the step.
    /// The wait goes through `runCancellable`, so a spoken stop ends it.
    private func waitForNewWindow(after actions: [Action], limit: Int) async -> WindowWait? {
        guard taskHarness == .agentDesktop, let harness,
              actions.contains(where: { if case .openURL = $0 { true } else if case .openApp = $0 { true } else { false } })
        else { return nil }
        let front = observer.frontWindow()
        guard front.frame == nil, !front.app.isEmpty else { return nil }
        let appOnly = !actions.contains { if case .openURL = $0 { true } else { false } }
        let command = DesktopCommand.wait(.event, value: DesktopEvent.windowOpened.rawValue, app: front.app, ref: nil, timeoutMs: min(limit, Self.windowWaitMs))
        var result: HarnessActionResult = .failed("cancelled")
        let start = now()
        await runCancellable { result = await harness.act(command) }
        _ = harness.takeOpenSurfaces()   // the wait's own report must not reach the next step
        let ms = Int(start.duration(to: now()) / .milliseconds(1))
        if case .delivered = result { return WindowWait(delivered: true, appOnly: appOnly, ms: ms) }
        return WindowWait(delivered: false, appOnly: appOnly, ms: ms)
    }

    /// One observation, run off the main actor (an AX walk can take up to its budget, ~1-2 s on a busy page),
    /// and how long it took in milliseconds. The overlay state and screen rects are read here, on the main actor.
    private func observeTimed(mode: Mode, readings: [String] = []) async -> (result: Observed, ms: Int, fromHarness: Bool) {
        let observer = self.observer
        let state = overlay.state
        let screens = observer.screenRects()
        let kind = taskHarness
        let surfaces = pendingSurfaces
        let limit = planLimit
        let start = now()
        let r = await Task.detached {
            await observer.observe(mode: mode, overlay: state, screens: screens, harnessKind: kind, readings: readings,
                                   surfaces: surfaces, limit: limit)
        }.value
        return ((r.observation, r.labels), Int(start.duration(to: now()) / .milliseconds(1)), r.fromHarness)
    }

    /// The picture for this step, or why there is none; announces which on the prompt's row first.
    private func pictureInput(for observation: ScreenObservation, step n: Int) async -> VisionInput {
        let input = await vision(for: observation)
        switch input {
        case .image: onStatus?(.running("step \(n) · \(Self.looking)"))
        case .unavailable(let why): onStatus?(.running("step \(n) · \(why)"))
        }
        return input
    }

    private func vision(for observation: ScreenObservation) async -> VisionInput {
        // A single-window capture would leave the open menu or sheet out; the element list already shows it.
        if observation.surface != nil { return .unavailable("a menu or sheet is open") }
        var badges: [Int: UIElementInfo] = [:]
        if case .labels(let shown) = overlay.state { badges = shown }
        switch await captureCancellable(badges: badges) {
        case .image(let shot): return .image(shot)
        case .notGranted: return .unavailable("screen recording not granted")
        case .failed: return .unavailable("screen capture failed")
        }
    }

    /// Races the capture against the deadline and against `cancel()`. ScreenCaptureKit cannot be cancelled and can
    /// hang, so the loser is never awaited: whichever finishes first resumes the one continuation, and a later
    /// finisher finds the wait already ended. A capture that loses counts as `.failed`.
    private func captureCancellable(badges: [Int: UIElementInfo]) async -> ScreenshotResult {
        guard let provider = screenshots, !isCancelled else { return .failed }
        captureWaitID += 1
        let id = captureWaitID
        let deadline = captureDeadline
        let result = await withCheckedContinuation { (wait: CheckedContinuation<ScreenshotResult, Never>) in
            captureWait = wait
            Task { @MainActor [weak self] in
                let shot = await provider.capture(badges: badges)
                self?.endCaptureWait(id: id, with: shot)
            }
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: deadline)
                self?.endCaptureWait(id: id, with: .failed)
            }
        }
        return isCancelled ? .failed : result
    }

    private func endCaptureWait(id: Int? = nil, with result: ScreenshotResult) {
        guard id == nil || id == captureWaitID, let wait = captureWait else { return }
        captureWait = nil
        wait.resume(returning: result)
    }

    /// Pauses the task until the user answers, `cancel()` is called or `timeout` passes (nil for the last two). The
    /// timeout runs on the injected `sleep`; its task is cancelled once the wait ends.
    private func awaitAnswer(timeout: Duration) async -> String? {
        guard !isCancelled else { return nil }
        answerWaitID += 1
        let id = answerWaitID
        let sleep = self.sleep
        var timer: Task<Void, Never>?
        let reply = await withCheckedContinuation { (wait: CheckedContinuation<String?, Never>) in
            answerWait = wait
            timer = Task { @MainActor [weak self] in
                await sleep(timeout)
                self?.endAnswerWait(id: id, with: nil)
            }
        }
        timer?.cancel()
        return isCancelled ? nil : reply
    }

    private func endAnswerWait(id: Int? = nil, with reply: String?) {
        guard id == nil || id == answerWaitID, let wait = answerWait else { return }
        answerWait = nil
        wait.resume(returning: reply)
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

    private func executeCancellable(_ actions: [Action], labels: [Int: UIElementInfo], tabs: TabListing?) async -> String? {
        let executor = self.executor
        var failure: String?
        await runCancellable { failure = await executor.execute(actions, labels: labels, tabs: tabs) }
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

    private func hasImage(_ v: VisionInput?) -> Bool { if case .image? = v { return true } else { return false } }

    static func stoppedHUD(_ intent: String) -> String { intent.isEmpty ? PipelineText.stopped : "stopped: \(intent)" }

    /// The finish line as a prompt status: the outcome's kind, `text`, and how many steps ran.
    static func finalStatus(_ outcome: TaskOutcome, text: String, steps: Int) -> PromptStatus {
        let line = steps > 0 ? "\(text) (\(steps) step\(steps == 1 ? "" : "s"))" : text
        switch outcome {
        case .done: return .done(line)
        case .stuck, .failed: return .failed(line)
        case .stopped: return .stopped(line)
        case .ignored: return .ignored(line)
        }
    }

    /// Reports what the task is doing now. Until the first step starts the board row shows the same words.
    private func setPhase(_ phase: TaskPhase) {
        guard trail.phase != phase else { return }
        trail.phase = phase
        onTrail?(trail)
        if trail.steps.isEmpty, let line = TaskPanelText.phaseLine(trail) { onStatus?(.running(line)) }
    }

    /// `hud` overrides the outcome's usual finish line.
    private func finish(_ outcome: TaskOutcome, hud: String? = nil) async -> TaskOutcome {
        // Spec Safety: a held mouse button is released on any exit; a successful `done` keeps what it did.
        if case .done = outcome {} else { executor.releaseAll() }
        observer.resetBrowserTokens()
        planLimit = nil
        if case .stuck(let why) = outcome { trail.ending = why == Self.stepLimit ? .stepCap : .stuck }
        trail.phase = nil
        onTrail?(trail)
        onStatus?(Self.finalStatus(outcome, text: hud ?? PipelineText.hud(for: outcome), steps: stepsRun))
        // The HUD is already up; ending the traced session is quick bookkeeping.
        if let id = sessionID, let harness {
            sessionID = nil
            await harness.endSession(id)
        }
        return outcome
    }
}
