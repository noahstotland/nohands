import Foundation
import NoHandsCore

/// mic -> VAD -> assembler -> (bounded queue, newest 2) -> ASR -> (serial job stream) -> ModeMachine -> executor / resolver.
///
/// Audio, VAD and ASR run off the main actor. Everything that touches the executor, overlay or mode machine
/// runs in ONE main-actor consumer task, so utterances are executed strictly one after another.
/// A multi-step task (`TaskRunner`) runs in `activeTask` so the consumer stays responsive: while it runs, a stop
/// phrase cancels it and any other utterance is held (newest only) and handled inside `activeTask` after the task
/// ends — a task and a command never execute concurrently.
@MainActor public final class VoicePipeline {
    public var onStatus: ((Mode, String) -> Void)?
    /// Non-fatal notices (e.g. slow warm-up).
    public var onNotice: ((String) -> Void)?
    /// Errors worth a status-line entry and a Retry (e.g. permanent microphone failure, failed warm-up).
    public var onError: ((String) -> Void)?

    private struct Job: Sendable {
        var transcript: String
        var trace: LatencyTrace
    }

    /// An utterance that routed to the LLM and runs as a task.
    private struct PendingTask {
        var goal: String
        var transcript: String
        var trace: LatencyTrace
    }

    private let config: AppConfig
    private let transcriber: any Transcribing
    /// nil when there is no resolver (LLM off): such utterances only show a hint.
    private let runner: TaskRunner?
    private let executor: ActionExecutor
    private let overlay: any OverlayPresenting
    private let ax: any ElementProviding

    private var modeMachine: ModeMachine
    private var vad: VoiceActivity?
    private var mic: MicrophoneCapture?
    private var tasks: [Task<Void, Never>] = []
    private var consumer: Task<Void, Never>?
    /// Bumped by every stop(). start() compares it after its last await so a stop() requested while start()
    /// was suspended (VAD load, warm-up) wins and the mic is never started.
    private var stopGeneration = 0
    /// True between stop()/pause() and the next start(); a job in flight at that moment must not execute.
    private var stopped = false
    private var starting = false
    private var warmedUp = false
    private var llmOffShown = false
    private var lastTranscript = ""
    private var merge: MergeBuffer?
    /// Runs the current task and then any held job. Non-nil means busy. Kept after stop() until it ends so start()
    /// can await it.
    private var activeTask: Task<Void, Never>?
    /// The newest utterance heard while a task ran; handled after the task ends.
    private var heldJob: Job?

    /// The outcome of the most recent task (for tests and diagnostics).
    private(set) var lastTaskOutcome: TaskOutcome?
    var isTaskActive: Bool { activeTask != nil }

    public var isRunning: Bool { mic != nil }
    public var mode: Mode { modeMachine.mode }

    /// `observer` defaults to one built on `ax`; the app passes one with a larger AX budget so web page content is
    /// reached. `taskRunner` lets tests inject a runner (e.g. with a no-op sleep); by default one is built from the
    /// resolver, executor, observer and overlay.
    public init(config: AppConfig, transcriber: any Transcribing, resolver: (any IntentResolving)?,
                executor: ActionExecutor, overlay: any OverlayPresenting, ax: any ElementProviding = AXQuery(),
                observer: ScreenObserver? = nil, taskRunner: TaskRunner? = nil) {
        self.config = config
        self.transcriber = transcriber
        let observer = observer ?? ScreenObserver(ax: ax, maxElements: config.maxObservedElements)
        self.runner = taskRunner ?? resolver.map {
            TaskRunner(config: config, resolver: $0, executor: executor, observer: observer, overlay: overlay)
        }
        self.executor = executor
        self.overlay = overlay
        self.ax = ax
        self.modeMachine = ModeMachine(grammar: CommandGrammar(config: config.grammarConfig))
        executor.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.modeMachine.apply(mode: mode)
            self.publishStatus()
        }
    }

    /// Only a complete grammar command in command mode skips the merge window.
    nonisolated private static func isComplete(_ transcript: String, mode: Mode, grammar: CommandGrammar) -> Bool {
        mode == .command && grammar.parse(transcript) != nil
    }

    /// Loads VAD, warms up ASR (first call only) and starts the microphone.
    public func start() async throws {
        guard mic == nil, !starting else { return }
        starting = true
        defer { starting = false }
        let requested = stopGeneration
        stopped = false

        // A consumer from a previous session may still be executing an utterance; let it finish first so
        // execution stays strictly serialized across pause/resume.
        await consumer?.value
        consumer = nil
        await activeTask?.value   // stop() cancelled it; it ends promptly

        if vad == nil { vad = try await VoiceActivity(silenceMs: config.silenceMs) }
        let vad = self.vad!
        await vad.reset()
        if !warmedUp { warmedUp = await warmUp() }

        guard requested == stopGeneration else { return }   // stop()/pause() arrived while we were loading

        let (chunks, chunkCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        // At most 2 pending utterances; when full the OLDEST is dropped.
        let (utterances, uttCont) = AsyncStream<(samples: [Float], at: ContinuousClock.Instant)>
            .makeStream(bufferingPolicy: .bufferingNewest(2))
        let (jobs, jobCont) = AsyncStream<Job>.makeStream(bufferingPolicy: .bufferingNewest(2))

        let grammar = CommandGrammar(config: config.grammarConfig)
        let merge = MergeBuffer(
            merger: UtteranceMerger(windowMs: config.mergeWindowMs, unfinishedWindowMs: config.mergeWindowUnfinishedMs),
            isComplete: { Self.isComplete($0, mode: $1, grammar: grammar) },
            onHold: { [weak self] text in
                Task { @MainActor in self?.overlay.showHUD(text + " …") }
            },
            emit: { text, trace in
                if case .dropped = jobCont.yield(Job(transcript: text, trace: trace)) {
                    PipelineLog.warning("busy: dropped oldest queued utterance")
                    Task { @MainActor [weak self] in self?.overlay.showHUD("skipped (busy)") }
                }
            })
        self.merge = merge
        await merge.set(mode: modeMachine.mode)

        let capture = try MicrophoneCapture()
        capture.onEvent = { [weak self] event in
            if case .failed(let message) = event {
                PipelineLog.error("[mic] failure", detail: message)
                Task { @MainActor in
                    guard let self else { return }
                    self.overlay.showHUD("microphone error")
                    self.stop()
                    self.onError?("microphone failed")
                }
            } else {
                PipelineLog.info("[mic] \(event)")
            }
        }

        let transcriber = self.transcriber

        let vadTask = Task.detached {
            var assembler = UtteranceAssembler()
            for await chunk in chunks {
                do {
                    let ev = try await vad.process(chunk)
                    if ev == .speechStart { await merge.speechStarted() }
                    if let utterance = assembler.push(chunk, event: ev) {
                        if case .dropped = uttCont.yield((utterance, .now)) {
                            PipelineLog.warning("asr backlog: dropped oldest pending utterance")
                        }
                    } else if ev == .speechEnd {
                        await merge.speechAbandoned()   // too short to transcribe
                    }
                } catch {
                    PipelineLog.error("vad error (state reset)", detail: "\(error)")
                    await vad.reset()
                    assembler.reset()
                }
            }
            uttCont.finish()
        }
        let asrTask = Task.detached {
            for await utterance in utterances {
                var trace = LatencyTrace()
                trace.speechEnd = utterance.at
                do {
                    let text = try await transcriber.transcribe(utterance.samples)
                    trace.asrDone = .now
                    if text.isEmpty {
                        await merge.speechAbandoned()
                    } else {
                        await merge.transcript(text, trace: trace)
                    }
                } catch {
                    PipelineLog.error("asr error (utterance skipped)", detail: "\(error)")
                    await merge.speechAbandoned()
                }
            }
            jobCont.finish()
        }
        // The single serial consumer: each job is fully handled (including awaiting the executor) before the next.
        let execTask = Task { @MainActor [weak self] in
            for await job in jobs {
                guard !Task.isCancelled, let self else { break }
                await self.handle(transcript: job.transcript, trace: job.trace)
            }
        }
        consumer = execTask
        tasks = [vadTask, asrTask]

        do {
            try capture.start { chunkCont.yield($0) }
        } catch {
            chunkCont.finish()
            tasks.forEach { $0.cancel() }
            tasks = []
            consumer?.cancel()
            throw error
        }
        mic = capture
        publishStatus()
    }

    /// Stops the microphone and drops any queued audio. Safe to call repeatedly.
    public func stop() {
        stopGeneration += 1
        stopped = true
        mic?.stop()
        mic = nil
        for t in tasks { t.cancel() }
        tasks = []
        executor.releaseAll()   // release a held mouse button and drop any grid/labels overlay
        heldJob = nil
        runner?.cancel()
        activeTask?.cancel()    // also covers a cancel() that lands before run() starts (run() clears its flag)
        if let merge { Task { await merge.reset() } }
        merge = nil
        consumer?.cancel()   // kept (not nil-ed) so start() can await an in-flight utterance
    }

    public func pause() { stop() }
    public func resume() async throws { try await start() }

    // MARK: - private

    /// Returns true when the warm-up transcription succeeded.
    private func warmUp() async -> Bool {
        let samples = (0..<16_000).map { _ in Float.random(in: -0.002...0.002) }
        let t0 = ContinuousClock.now
        do {
            _ = try await transcriber.transcribe(samples)
        } catch {
            PipelineLog.error("[asr] warm-up failed", detail: "\(error)")
            onError?("warm-up failed")
            return false
        }
        let ms = Int(t0.duration(to: .now) / .milliseconds(1))
        PipelineLog.info("[asr] warm-up transcription took \(ms) ms")
        if ms > 300 {
            PipelineLog.warning("[asr] warm-up took \(ms) ms (> 300 ms); recognition may be slow")
            onNotice?("ASR warm-up slow (\(ms) ms)")
        }
        return true
    }

    /// Checked immediately before every executor call: a job in flight at Pause must never execute afterwards.
    private var canExecute: Bool { !Task.isCancelled && !stopped }

    private func publishStatus() {
        onStatus?(modeMachine.mode, lastTranscript)
        if let merge { let m = modeMachine.mode; Task { await merge.set(mode: m) } }
    }

    /// Routes one transcript and executes it. Internal so tests can drive the pipeline without audio.
    /// Returns once the utterance is handled; an LLM utterance only starts a task (see `waitForTask()`).
    func handle(transcript text: String, trace: LatencyTrace) async {
        let job = Job(transcript: text, trace: trace)
        if activeTask != nil { busy(job); return }
        if let pending = await process(job, checkStale: true) { startTask(pending) }
    }

    /// Waits until no task is running (including held jobs handled after it). For tests.
    func waitForTask() async {
        while let task = activeTask { await task.value }
    }

    /// An utterance arrived while a task runs: a stop phrase cancels the task (and drops the held job); anything
    /// else replaces the held job.
    private func busy(_ job: Job) {
        guard !stopped else { return }
        if StopWords.isStop(job.transcript) {
            heldJob = nil
            runner?.cancel()
            activeTask?.cancel()   // the runner shows "stopped" when it unwinds
            PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "stop", detail: "stop")
        } else {
            heldJob = job
            overlay.showHUD(PipelineText.busySayStop)
            PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "held", detail: "held")
        }
    }

    /// Routes and executes one job. Returns the task to run when it routed to the LLM (logged when the task ends).
    private func process(_ job: Job, checkStale: Bool) async -> PendingTask? {
        let text = job.transcript
        var trace = job.trace
        if checkStale, let spoke = trace.speechEnd, StaleJobPolicy.isStale(age: spoke.duration(to: .now)) {
            PipelineLog.warning("busy: skipped stale utterance (older than 8 s)")
            overlay.showHUD("skipped (busy)")
            return nil
        }
        lastTranscript = text
        var routing = modeMachine.route(text)
        // A stop phrase with no task running must not start one (held jobs never get here: busy() intercepts them).
        if case .resolveWithLLM(let phrase) = routing, StopWords.isStop(phrase) { routing = .ignore(reason: "stop") }
        var outcome = PipelineText.summary(routing)                    // public: kinds only
        var detail = PipelineText.summary(routing, detailed: true)     // private: with payloads

        switch routing {
        case .ignore:
            break   // nothing on the HUD (this also keeps sleep silent)
        case .execute(let actions):
            overlay.showHUD(text)
            guard canExecute else { outcome += " (cancelled)"; detail += " (cancelled)"; break }
            if let failure = await executor.execute(actions) {
                outcome += " FAILED"
                detail += " FAILED(\(failure))"
            }
        case .resolveWithLLM(let phrase):
            overlay.showHUD(text)
            if runner == nil {
                showNoResolverHint()
                outcome += " (no resolver)"; detail += " (no resolver)"
            } else if !canExecute {
                outcome += " (cancelled)"; detail += " (cancelled)"
            } else {
                return PendingTask(goal: phrase, transcript: text, trace: trace)
            }
        }

        trace.actionsDone = .now
        PipelineLog.utterance(trace: trace, transcript: text, outcome: outcome, detail: detail)
        publishStatus()
        return nil
    }

    /// Runs `first` in `activeTask`, then the held job (if any) inside the same task so it stays serialized; a held
    /// job that routes to the LLM runs as the next task.
    private func startTask(_ first: PendingTask) {
        guard let runner else { return }
        activeTask = Task { [self] in
            var next: PendingTask? = first
            while let pending = next {
                next = nil
                await runTask(pending, runner: runner)
                while next == nil, canExecute, let held = heldJob {
                    heldJob = nil
                    next = await process(held, checkStale: false)   // already waited; don't drop it as stale
                }
            }
            activeTask = nil
        }
    }

    private func runTask(_ pending: PendingTask, runner: TaskRunner) async {
        let outcome = await runner.run(goal: pending.goal, mode: modeMachine.mode)   // shows its own HUDs
        lastTaskOutcome = outcome
        var trace = pending.trace
        trace.actionsDone = .now
        let steps = runner.stepsRun
        PipelineLog.utterance(trace: trace, transcript: pending.transcript,
                              outcome: "task(\(Self.kind(outcome)), steps=\(steps))",
                              detail: "task(\(Self.kind(outcome, detailed: true)), steps=\(steps))")
        publishStatus()
    }

    private func showNoResolverHint() {
        if llmOffShown {
            overlay.showHUD(PipelineText.didntCatch)
        } else {
            llmOffShown = true
            overlay.showHUD(config.intentBackend == .off ? PipelineText.llmDisabled : PipelineText.llmOff)
        }
    }

    /// Outcome kind for the log; `detailed` adds the model's text (private log field only).
    private static func kind(_ outcome: TaskOutcome, detailed: Bool = false) -> String {
        switch outcome {
        case .done(let s): detailed ? "done: \(s)" : "done"
        case .stuck(let s): detailed ? "stuck: \(s)" : "stuck"
        case .ignored: "ignored"
        case .stopped: "stopped"
        case .failed(let s): detailed ? "failed: \(s)" : "failed"
        }
    }
}
