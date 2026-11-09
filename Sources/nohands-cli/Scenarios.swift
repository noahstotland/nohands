import Foundation
import NoHandsCore
import NoHandsMac

/// The check observer never hears audio, so `media` is `playing` only when a Pause control is on screen.
private struct NoAudio: AudioOutputProbing { func isPlaying() -> Bool { false } }

/// Ctrl-C state for the whole suite (main actor only).
@MainActor private final class SuiteControl {
    var policy = InterruptPolicy()
    var stop = false
    var runner: TaskRunner?
}

private func macModel() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buf)
}

private func seconds(_ d: Duration) -> Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }

private func taskEnd(_ outcome: TaskOutcome) -> TaskEnd {
    switch outcome {
    case .done: return .done
    case .stuck: return .stuck
    case .failed: return .failed
    case .ignored: return .ignored
    case .stopped: return .stopped
    }
}

private struct Seen {
    var observation: ScreenObservation
    var labels: [Int: UIElementInfo]
}

/// The check observer: its own element cap and no audio hint, so a verdict never rests on another app's sound.
@MainActor private final class Looker {
    private let query = AXQuery(budget: .milliseconds(1000), maxNodes: 6000)
    private let checker: ScreenObserver
    private let hasHarness: Bool
    private let control: SuiteControl

    init(harness: (any DesktopHarness)?, snapshotMs: Int, control: SuiteControl) {
        checker = ScreenObserver(ax: query, maxElements: 300, harness: harness, snapshotTimeoutMs: snapshotMs, audio: NoAudio())
        hasHarness = harness != nil
        self.control = control
    }

    func fresh() async -> Seen {
        _ = query.actionableElements()   // exposes a Chromium page tree, which appears ~0.5 s later
        try? await Task.sleep(for: .seconds(1))
        // `observe` falls back to the native walk by itself when agent-desktop cannot read the window.
        let r = await checker.observe(mode: .command, overlay: .none, harnessKind: hasHarness ? .agentDesktop : .native)
        return Seen(observation: r.observation, labels: r.labels)
    }

    /// Looks at the screen until `ok` holds, `limit` passes or Ctrl-C; always looks at least once.
    func poll(for limit: Duration, until ok: (ScreenObservation) -> Bool) async -> (held: Bool, last: Seen) {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while true {
            let seen = await fresh()
            if ok(seen.observation) { return (true, seen) }
            if control.stop || ContinuousClock.now >= deadline { return (false, seen) }
        }
    }
}

/// `nohands-cli scenarios [file] [--only name]`: runs each scripted goal for real and scores it against an
/// independent screen check. Returns the exit status: 0 when every scenario passed, 2 otherwise.
@MainActor func runScenarios(_ args: [String]) async -> Int32 {
    let synth = CGEventInputSynthesizer()
    var path = "scripts/task-scenarios.json"
    var only: String?
    var positional: [String] = []
    var i = 0
    while i < args.count {
        if args[i] == "--only" {
            guard i + 1 < args.count else { usage() }
            only = args[i + 1]
            i += 2
        } else { positional.append(args[i]); i += 1 }
    }
    guard positional.count <= 1 else { usage() }
    if let p = positional.first { path = p }

    let data: Data
    do { data = try Data(contentsOf: URL(fileURLWithPath: path)) } catch { fail("cannot read \(path): \(error.localizedDescription)") }
    var scenarios: [TaskScenario]
    do { scenarios = try ScenarioFile.load(data, run: Int(Date().timeIntervalSince1970)) }
    catch { fail("\(path): \(sanitized(error.localizedDescription))") }
    guard !scenarios.isEmpty else { fail("\(path): no scenarios") }
    if let only {
        scenarios = scenarios.filter { $0.name == only }
        guard !scenarios.isEmpty else { fail("no scenario named \(sanitized(only)) in \(path)") }
    }

    let loaded: (config: AppConfig, resolver: any IntentResolving, model: String)
    do { loaded = try loadResolver() } catch { fail("error: \(error)") }
    let config = loaded.config, resolver = loaded.resolver, modelName = loaded.model
    guard Permissions.accessibilityGranted(prompt: false) else {
        fail("Accessibility permission is not granted to this process (or its terminal). Enable it in System Settings > Privacy & Security > Accessibility, then rerun.")
    }
    let backend = config.effectiveBackend == .claude ? "claude" : "local"
    print("scenarios: \(scenarios.count)  (backend=\(backend), model=\(modelName), mac=\(macModel()))")
    let harness = await loadHarness(config)
    print("close any tabs a previous run left open; starting in 3 s...")
    try? await Task.sleep(for: .seconds(3))

    var results: [ScenarioResult] = []
    await runOverlay { overlay in
        let control = SuiteControl()
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        interrupt.setEventHandler {
            MainActor.assumeIsolated {
                switch control.policy.interrupt() {
                case .stopTask:
                    print("stopping... (Ctrl-C again to quit now)")
                    control.stop = true
                    control.runner?.cancel()
                case .exitNow:
                    exit(InterruptPolicy.exitStatus)
                }
            }
        }
        interrupt.resume()
        defer { interrupt.cancel() }

        let looker = Looker(harness: harness, snapshotMs: config.agentDesktopSnapshotMs, control: control)

        for (index, sc) in scenarios.enumerated() {
            if control.stop {
                results.append(ScenarioResult(name: sc.name, verdict: .notRun, steps: 0, seconds: 0))
                continue
            }
            print("\n[\(index + 1)/\(scenarios.count)] \(sanitized(sc.name)): \(sanitized(sc.goal))")
            let started: Bool
            switch sc.start {
            case .app(let name): started = AXQuery().activate(appNamed: name)
            case .url(let url): started = AXQuery().open(url: url, appNamed: nil) != nil
            }
            var ready = false
            if started {
                ready = await looker.poll(for: .seconds(20)) { o in
                    TaskScenario.startHolds(sc.start, in: o) && sc.ready.allSatisfy { $0.holds(in: o) }
                }.held
            }
            if control.stop {
                results.append(ScenarioResult(name: sc.name, verdict: .stopped, steps: 0, seconds: 0))
                print("\(ScenarioVerdict.stopped.rawValue)")
                continue
            }
            guard ready else {
                results.append(ScenarioResult(name: sc.name, verdict: .startFailed, steps: 0, seconds: 0))
                print("\(ScenarioVerdict.startFailed.rawValue)  (\(started ? "start state not reached in 20 s" : "could not start"))")
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            var cfg = config
            cfg.maxTaskSteps = sc.maxSteps
            cfg.maxMediaTaskSteps = sc.maxSteps
            let executor = ActionExecutor(input: synth, ax: AXQuery(), overlay: overlay, config: cfg, harness: harness)
            // Same observer as the app's task loop: a larger AX budget so web page content is reached.
            let observer = ScreenObserver(ax: AXQuery(budget: .milliseconds(1000), maxNodes: 6000),
                                          maxElements: cfg.observedElementCap, harness: harness,
                                          snapshotTimeoutMs: cfg.agentDesktopSnapshotMs)
            let runner = TaskRunner(config: cfg, resolver: resolver, executor: executor,
                                    observer: observer, overlay: overlay, harness: harness,
                                    screenshots: cfg.visionEnabled ? WindowScreenshotter(ax: AXQuery()) : nil)
            let t0 = ContinuousClock.now
            var last = t0
            runner.onStatus = { status in if status.isFinal { print("status: \(sanitized(status.text))") } }
            runner.onStep = { n, step, settle, failure in
                let now = ContinuousClock.now
                print("step \(n): \(sanitized(step.intent)) -> \(ActionSummary.kinds(step.actions)) (settle \(ms(settle)) ms, step \(ms(last.duration(to: now))) ms)")
                print("        \(step.status.rawValue) \(step.actions)")
                if let failure { print("        failed: \(failure)") }
                last = now
            }
            control.runner = runner
            let outcome = await runner.run(goal: sc.goal, mode: .command)
            control.runner = nil
            var end = taskEnd(outcome)
            if control.stop { end = .stopped }

            var verdict = ScenarioVerdict.stopped
            var finalSeen: Seen?
            if end != .stopped {
                let checked = await looker.poll(for: .seconds(3)) { o in sc.success.allSatisfy { $0.holds(in: o) } }
                finalSeen = checked.last
                if control.stop { end = .stopped }
                else {
                    verdict = TaskScenario.verdict(end: end, checksHold: checked.held)
                    if !checked.held {
                        let o = checked.last.observation
                        for c in sc.success where !c.holds(in: o) {
                            print("        check failed: \(sanitized(c.label))  (window: \(sanitized(o.windowTitle)), url: \(sanitized(o.url ?? "-")))")
                        }
                    }
                }
            }
            let elapsed = seconds(t0.duration(to: .now))
            results.append(ScenarioResult(name: sc.name, verdict: verdict, steps: runner.stepsRun, seconds: elapsed))
            print("\(verdict.rawValue)  steps=\(runner.stepsRun)  \(String(format: "%.1f", elapsed)) s")

            // Pause what the scenario started, so sound does not run into the next one.
            if let seen = finalSeen, !control.stop, sc.success.contains(.mediaPlaying) {
                if let pause = seen.observation.elements.first(where: {
                    MediaSignal.control(role: $0.role, name: $0.title, value: $0.value) == .pause
                }) {
                    await executor.execute([.click(.label(pause.number), button: .left, count: 1)], labels: seen.labels)
                }
            }
            if !control.stop { try? await Task.sleep(for: .seconds(2)) }
        }
        try? await Task.sleep(for: .milliseconds(1800))   // let the last outcome HUD show
    }

    print("\n\(ScenarioReport.summary(results))\n")
    print(ScenarioReport.table(results))
    return results.allSatisfy { $0.verdict == .pass } ? 0 : 2
}
