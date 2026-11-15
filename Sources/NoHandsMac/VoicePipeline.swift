import Foundation
import AppKit
import NoHandsCore

/// mic -> VAD -> assembler -> (bounded queue, newest 4: early and full jobs) -> ASR -> (serial job stream) -> ModeMachine -> executor / resolver.
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
        /// The prompt's row on the board.
        var id: Int
        var transcript: String
        var trace: LatencyTrace
        /// The row is already on the board (the merge window showed the words as they were spoken).
        var shown = false
    }

    /// An utterance that routed to the LLM and runs as a task.
    private struct PendingTask {
        var id: Int
        var goal: String
        var transcript: String
        var trace: LatencyTrace
    }

    private let config: AppConfig
    private let attention: AttentionGate
    private let transcriber: any Transcribing
    /// nil when there is no resolver (LLM off): such utterances only show a hint.
    /// A `var` so the app can change backend live (see `switchBackend`). While a task runs it stays the runner running
    /// it, so a stop phrase always reaches that runner; a new one waits in `pendingRunner`.
    private var runner: TaskRunner?
    /// The runner a switch asked for while a task was running; it takes over when the task loop is between runs.
    private var pendingRunner: TaskRunner?
    private let harness: (any DesktopHarness)?
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
    /// Held jobs a stop phrase discarded; reported ("dropped") once the stopped task has unwound.
    private var droppedJobs: [Job] = []
    /// A held job is replayed after the task only if it was spoken within this window.
    static let heldJobMaxAge: Duration = .seconds(60)
    /// Prompt rows are numbered in the order heard.
    private var nextPromptID = 0
    /// The row the merge window opened for words still being spoken; the job they become takes it over.
    private var listeningID: Int?

    private func newPromptID() -> Int {
        nextPromptID += 1
        return nextPromptID
    }

    /// The merge window is holding `text` for more words: show it as a prompt that is still being spoken.
    private func listening(_ text: String) {
        guard !stopped else { return }
        let id = listeningID ?? newPromptID()
        listeningID = id
        overlay.report(id, text: text, status: .listening)
    }


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
                observer: ScreenObserver? = nil, taskRunner: TaskRunner? = nil, harness: (any DesktopHarness)? = nil) {
        self.config = config
        self.attention = config.attentionGate
        self.transcriber = transcriber
        let observer = observer ?? ScreenObserver(ax: ax, maxElements: config.observedElementCap, harness: harness,
                                                  snapshotTimeoutMs: config.agentDesktopSnapshotMs)
        self.runner = taskRunner ?? resolver.map {
            TaskRunner(config: config, resolver: $0, executor: executor, observer: observer, overlay: overlay, harness: harness,
                       screenshots: config.visionEnabled ? WindowScreenshotter(ax: ax) : nil)
        }
        self.executor = executor
        self.overlay = overlay
        self.ax = ax
        self.harness = harness
        self.modeMachine = ModeMachine(grammar: CommandGrammar(config: config.grammarConfig), attention: config.attentionGate)
        executor.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.modeMachine.apply(mode: mode)
            self.publishStatus()
        }
    }

    /// Moves new tasks to another backend from the next command on, without stopping the microphone. Builds a runner
    /// like `init` does (screenshots follow `config.visionEnabled`); a task already running finishes on its own
    /// runner, and a command held behind it goes to the new one. Other settings in `config` are not re-read.
    public func switchBackend(config: AppConfig, resolver: any IntentResolving, observer: ScreenObserver) {
        replaceRunner(TaskRunner(config: config, resolver: resolver, executor: executor, observer: observer,
                                 overlay: overlay, harness: harness,
                                 screenshots: config.visionEnabled ? WindowScreenshotter(ax: ax) : nil))
    }

    /// Takes `new` at once when no task is running; otherwise holds it (the newest wins) until the task loop is between runs.
    func replaceRunner(_ new: TaskRunner) {
        if activeTask == nil { runner = new; pendingRunner = nil } else { pendingRunner = new }
    }

    /// Called only where no runner is running: between runs inside the task loop.
    private func applyPendingRunner() {
        if let pendingRunner { runner = pendingRunner }
        pendingRunner = nil
    }

    /// Skips the merge window: a complete grammar command in command mode, a stop phrase in any mode, and the
    /// dictation commands (escape phrases, "scratch that", "delete word") in dictation mode. Internal so tests build their MergeBuffer the same way.
    /// With the attention word on, a command mode grammar command counts only after the word ("computer, go back").
    nonisolated static func isComplete(_ transcript: String, mode: Mode, grammar: CommandGrammar,
                                       attention: AttentionGate = .off, frontmost: String? = nil) -> Bool {
        if attention.isStop(transcript) { return true }
        switch mode {
        case .command:
            // "spell" always waits the merge window: a pause mid-spelling must not type half and send the rest to the model.
            func complete(_ phrase: String) -> Bool { CommandGrammar.normalize(phrase).first != "spell" && grammar.parse(phrase, frontmost: frontmost) != nil }
            switch attention.check(transcript) {
            case .off: return complete(transcript)
            case .addressed(let rest): return complete(rest)
            case .wordOnly, .notAddressed: return false
            }
        case .dictation: return ModeMachine.isDictationCommand(transcript, attention: attention)
        case .sleep: return false
        }
    }

    /// True when the grammar parses `transcript` (after the attention word) to actions carrying spoken text, or does not
    /// parse it at all: such a command keeps the full silence window.
    nonisolated static func carriesSpokenText(_ transcript: String, grammar: CommandGrammar,
                                              attention: AttentionGate = .off, frontmost: String? = nil) -> Bool {
        var phrase = transcript
        if case .addressed(let rest) = attention.check(transcript) { phrase = rest }
        return grammar.parse(phrase, frontmost: frontmost)?.carriesSpokenText ?? true
    }

    /// One unit of work for the serial ASR loop. `early` is a pass over the audio so far, started after a short
    /// silence while the utterance is still open; `full` is the closed utterance.
    struct ASRJob: Sendable {
        enum Kind: Sendable { case early, full }
        var kind: Kind
        var segment: UtteranceSegment
        /// When the job was created: the full job's utterance end, or the moment of the short silence.
        var at: ContinuousClock.Instant
        /// When the last voiced chunk arrived.
        var voiceEnd: ContinuousClock.Instant?
    }

    /// The ASR loop: transcribes jobs one at a time, so an early pass always finishes before the full pass of its
    /// segment. Internal so tests can drive it with a fake transcriber.
    nonisolated static func runASR(_ jobs: AsyncStream<ASRJob>, transcriber: any Transcribing, merge: MergeBuffer) async {
        var ledger = EarlyCloseLedger()
        for await job in jobs {
            var trace = LatencyTrace()
            trace.speechEnd = job.at
            trace.voiceEnd = job.voiceEnd
            switch job.kind {
            case .early:
                // The utterance is still open: a pass that is skipped, fails or hears nothing changes nothing.
                guard let audio = ledger.audio(forEarly: job.segment) else { continue }
                do {
                    let text = try await transcriber.transcribe(audio)
                    trace.asrDone = .now
                    // Record only an accepted early close; a rejected one leaves the whole segment to the full pass.
                    if !text.isEmpty, await merge.earlyTranscript(text, trace: trace) {
                        ledger.recordEarlyClose(job.segment)
                    }
                } catch {
                    PipelineLog.error("asr error (early pass skipped)", detail: "\(error)")
                }
            case .full:
                guard let audio = ledger.audio(forFull: job.segment) else {
                    await merge.speechAbandoned()   // an early close already used all the voiced audio
                    continue
                }
                do {
                    let text = try await transcriber.transcribe(audio)
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
        }
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
        // stop() always cancels activeTask, so the old task's held-job loop sees Task.isCancelled and ends promptly.
        await activeTask?.value

        if vad == nil { vad = try await VoiceActivity(silenceMs: config.silenceMs, earlySilenceMs: config.earlySilenceMs) }
        let vad = self.vad!
        await vad.reset()
        if !warmedUp { warmedUp = await warmUp() }

        guard requested == stopGeneration else { return }   // stop()/pause() arrived while we were loading

        let (chunks, chunkCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        // At most 4 pending jobs (early passes share the queue with utterances); when full the OLDEST is dropped.
        let (utterances, uttCont) = AsyncStream<ASRJob>.makeStream(bufferingPolicy: .bufferingNewest(4))
        let (jobs, jobCont) = AsyncStream<Job>.makeStream(bufferingPolicy: .bufferingNewest(2))

        let grammar = CommandGrammar(config: config.grammarConfig)
        let attention = self.attention
        let front = FrontmostApp.shared   // a pack phrase closes the merge window early, like a global one
        let merge = MergeBuffer(
            merger: UtteranceMerger(windowMs: config.mergeWindowMs, unfinishedWindowMs: config.mergeWindowUnfinishedMs),
            gate: attention,
            isComplete: { Self.isComplete($0, mode: $1, grammar: grammar, attention: attention, frontmost: front.bundleID) },
            carriesSpokenText: { Self.carriesSpokenText($0, grammar: grammar, attention: attention, frontmost: front.bundleID) },
            onHold: { [weak self] text in
                Task { @MainActor in self?.listening(text) }
            },
            emit: { text, trace in
                // The row id is given on the main actor when the job is handled (see `handle`).
                if case .dropped = jobCont.yield(Job(id: 0, transcript: text, trace: trace)) {
                    PipelineLog.warning("busy: dropped oldest queued utterance")
                    Task { @MainActor [weak self] in self?.overlay.showHUD(PipelineText.skippedBusy) }
                }
            })
        self.merge = merge
        await merge.set(mode: modeMachine.mode)

        let echoWanted = config.echoCancellation
        let capture = try MicrophoneCapture(echoCancellation: echoWanted)
        capture.onEvent = { [weak self] event in
            if case .failed(let message) = event {
                PipelineLog.error("[mic] failure", detail: message)
                Task { @MainActor in
                    guard let self else { return }
                    self.overlay.showHUD("microphone error")
                    self.stop()
                    self.onError?("microphone failed")
                }
            } else if case .echoCancellation(false) = event, echoWanted {
                PipelineLog.warning("[mic] echo cancellation unavailable; listening without it")
            } else {
                PipelineLog.info("[mic] \(event)")
            }
        }

        let transcriber = self.transcriber

        let vadTask = Task.detached {
            var assembler = UtteranceAssembler()
            var voiceEnd: ContinuousClock.Instant?
            for await chunk in chunks {
                do {
                    let step = try await vad.analyze(chunk)
                    let ev = step.event
                    if ev == .speechStart { await merge.speechStarted() }
                    if step.voiced { voiceEnd = .now }
                    if let segment = assembler.pushSegment(chunk, event: ev, voiced: step.voiced) {
                        let job = ASRJob(kind: .full, segment: segment, at: .now, voiceEnd: voiceEnd)
                        if case .dropped = uttCont.yield(job) {
                            PipelineLog.warning("asr backlog: dropped oldest pending utterance")
                        }
                    } else if ev == .speechEnd {
                        await merge.speechAbandoned()   // too short to transcribe
                    } else if ev == .earlySilence, await merge.wantsEarlyPass, let segment = assembler.snapshot() {
                        uttCont.yield(ASRJob(kind: .early, segment: segment, at: .now, voiceEnd: voiceEnd))
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
            await Self.runASR(utterances, transcriber: transcriber, merge: merge)
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
        for job in [heldJob].compactMap({ $0 }) + droppedJobs { reportDropped(job, log: false) }
        heldJob = nil
        droppedJobs = []
        modeMachine.forgetDictationRecord()   // "scratch that" after a pause must not delete text it never typed
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
        // The words the merge window was showing become this prompt's row; otherwise it gets a new one.
        let job = Job(id: listeningID ?? newPromptID(), transcript: text, trace: trace, shown: listeningID != nil)
        listeningID = nil
        if activeTask != nil { busy(job); return }
        if let pending = await process(job) { startTask(pending) }
    }

    /// Waits until no task is running (including held jobs handled after it). For tests.
    func waitForTask() async {
        while let task = activeTask { await task.value }
    }

    /// An utterance arrived while a task runs: a stop phrase cancels the task (and drops the held job); while the
    /// task waits for a spoken yes, the words are its answer (a yes needs the attention word when one is set; any
    /// other reply only stops the task); anything else replaces the held job.
    private func busy(_ job: Job) {
        guard !stopped else { return }
        if attention.isStop(job.transcript) {
            if let held = heldJob {
                // Shown as stopped, not dropped: the corner panel must stay clear after a stop (`TaskPanelText`).
                overlay.report(held.id, text: held.transcript, status: .stopped(PipelineText.dropped))
                PipelineLog.utterance(trace: held.trace, transcript: held.transcript, outcome: "dropped", detail: "dropped")
            }
            heldJob = nil
            runner?.cancel()
            activeTask?.cancel()   // the task's row shows "stopped" when the runner unwinds
            overlay.report(job.id, text: job.transcript, status: .stopped(PipelineText.stopping))
            PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "stop", detail: "stop")
        } else if let runner, runner.isAwaitingAnswer {
            runner.answer(job.transcript)
            overlay.report(job.id, text: job.transcript, status: .done(job.transcript))
            PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "answer", detail: "answer")
        } else if isUnaddressed(job.transcript) {
            // Stray speech must not replace a real held command: drop it, silently.
            if job.shown { overlay.report(job.id, text: job.transcript, status: .ignored("")) }
            PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "ignore(not addressed)", detail: "ignore(not addressed)")
        } else {
            if let replaced = heldJob { reportDropped(replaced) }   // newest wins; the old row must not stay "held"
            heldJob = job
            overlay.report(job.id, text: job.transcript, status: .held)
            PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "held", detail: "held")
        }
    }

    /// Command mode with the attention word on, and the transcript does not address it (or is only the word).
    private func isUnaddressed(_ transcript: String) -> Bool {
        guard attention.isOn, modeMachine.mode == .command else { return false }
        switch attention.check(transcript) {
        case .notAddressed, .wordOnly: return true
        case .addressed, .off: return false
        }
    }

    /// Shows a job that will never run as dropped on its row.
    private func reportDropped(_ job: Job, log: Bool = true) {
        overlay.report(job.id, text: job.transcript, status: .dropped(PipelineText.dropped))
        if log { PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "dropped", detail: "dropped") }
    }

    /// Routes and executes one job. Returns the task to run when it routed to the LLM (logged when the task ends).
    /// `held` marks a job that waited for a task: it gets the longer age limit and a "dropped" HUD when too old.
    private func process(_ job: Job, held: Bool = false) async -> PendingTask? {
        let text = job.transcript
        var trace = job.trace
        let maxAge = held ? Self.heldJobMaxAge : StaleJobPolicy.defaultMaxAge
        if let spoke = trace.speechEnd, StaleJobPolicy.isStale(age: spoke.duration(to: .now), maxAge: maxAge) {
            PipelineLog.warning("busy: skipped (stale) utterance (older than \(maxAge))")
            overlay.report(job.id, text: text, status: .dropped(held ? PipelineText.dropped : PipelineText.skippedBusy))
            return nil
        }
        lastTranscript = text
        var routing = modeMachine.route(text, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        // A stop phrase with no task running must not start one (held jobs never get here: busy() intercepts them).
        if case .resolveWithLLM(let phrase) = routing, StopWords.isStop(phrase) { routing = .ignore(reason: "stop") }
        var outcome = PipelineText.summary(routing)                    // public: kinds only
        var detail = PipelineText.summary(routing, detailed: true)     // private: with payloads

        switch routing {
        case .ignore(let reason):
            // Nothing on the board (this also keeps sleep silent), unless the merge window already put the words
            // there: that row must not stay "listening".
            if job.shown { overlay.report(job.id, text: text, status: .ignored(reason == "sleeping" ? "asleep" : "")) }
        case .reject(let message):
            overlay.report(job.id, text: text, status: .failed(message))
        case .execute(let actions):
            overlay.report(job.id, text: text, status: .heard)
            guard canExecute else {
                overlay.report(job.id, text: text, status: .dropped(PipelineText.cancelled))
                outcome += " (cancelled)"; detail += " (cancelled)"; break
            }
            let failure = await executor.execute(actions)
            let reading = executor.takeReadings().first   // "is it playing" answers on the row
            if let failure {
                overlay.report(job.id, text: text, status: .failed(failure))
                outcome += " FAILED"
                detail += " FAILED(\(failure))"
            } else {
                overlay.report(job.id, text: text, status: .done(reading ?? ""))
            }
        case .resolveWithLLM(let phrase):
            overlay.report(job.id, text: text, status: .heard)
            if runner == nil {
                overlay.report(job.id, text: text, status: .ignored(noResolverHint()))
                outcome += " (no resolver)"; detail += " (no resolver)"
            } else if !canExecute {
                overlay.report(job.id, text: text, status: .dropped(PipelineText.cancelled))
                outcome += " (cancelled)"; detail += " (cancelled)"
            } else {
                return PendingTask(id: job.id, goal: phrase, transcript: text, trace: trace)
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
        guard runner != nil else { return }
        activeTask = Task { [self] in
            var next: PendingTask? = first
            while let pending = next {
                next = nil
                applyPendingRunner()
                guard let runner else { break }
                await runTask(pending, runner: runner)
                applyPendingRunner()
                while next == nil, canExecute, let held = heldJob {
                    heldJob = nil
                    next = await process(held, held: true)   // it waited on purpose: longer limit
                }
            }
            // Still held here means the task was stopped: it must never run (e.g. in the next task).
            let lost = [heldJob].compactMap { $0 } + droppedJobs
            heldJob = nil
            droppedJobs = []
            if !stopped { for job in lost { reportDropped(job) } }
            applyPendingRunner()
            activeTask = nil
        }
    }

    private func runTask(_ pending: PendingTask, runner: TaskRunner) async {
        // The runner's step and finish lines go on this prompt's row.
        let id = pending.id, text = pending.transcript
        runner.onStatus = { [weak self] status in self?.overlay.report(id, text: text, status: status) }
        runner.onTrail = { [weak self] trail in self?.overlay.report(id, trail: trail) }
        let outcome = await runner.run(goal: pending.goal, mode: modeMachine.mode)
        runner.onStatus = nil
        runner.onTrail = nil
        lastTaskOutcome = outcome
        var trace = pending.trace
        trace.actionsDone = .now
        let steps = runner.stepsRun
        // Each step's settle wait in ms ("settle=120+300+90"); numbers only, so it is safe in the public field.
        let settle = runner.settleTimes.isEmpty ? "" : ", settle=" + runner.settleTimes.map(String.init).joined(separator: "+")
        PipelineLog.utterance(trace: trace, transcript: pending.transcript,
                              outcome: "task(\(Self.kind(outcome)), steps=\(steps)\(settle))",
                              detail: "task(\(Self.kind(outcome, detailed: true)), steps=\(steps)\(settle))")
        publishStatus()
    }

    /// Why an unmatched utterance ran nothing: the LLM-off hint once, then "didn't catch that".
    private func noResolverHint() -> String {
        if llmOffShown { return PipelineText.didntCatch }
        llmOffShown = true
        return config.intentBackend == .off ? PipelineText.llmDisabled : PipelineText.llmOff
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
