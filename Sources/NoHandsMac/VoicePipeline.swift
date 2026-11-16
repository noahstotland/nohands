import Foundation
import AppKit
import os
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
        /// Set for a rewrite of the selection: it waits on the model like a task, so it holds the task slot (a spoken
        /// stop cancels it and other speech waits) but needs no runner.
        var rewrite: RewriteInstruction?
        /// Set when the utterance named a macro: `goal` is its name and the steps run inside the same `activeTask`.
        var macro: Macro?
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
    /// The last task a follow-up ("no, the other one") may refer to, and when it ended. Grammar commands leave it
    /// alone; a task that is not a follow-up, a mode change and a backend switch replace or clear it.
    private var lastTask: EarlierTask?
    private var lastTaskEnded = ContinuousClock.now
    /// Bumped by `replaceRunner`; a task that started under another value must not keep its result as memory.
    private var runnerGeneration = 0
    private let harness: (any DesktopHarness)?
    private let executor: ActionExecutor
    private let overlay: any OverlayPresenting
    private let ax: any ElementProviding
    /// Where each command that ran is recorded for the View Logs window; nil records nothing.
    private let commandLog: CommandLogStore?
    /// Which model a task is attributed to in the log. The app sets it when it builds or switches the resolver.
    public var resolverKind: CommandLogEntry.Resolver = .claude

    private var modeMachine: ModeMachine
    /// Pause after a macro's grammar step, so an app the step opened can come forward. Tests set it to zero.
    var macroStepPause: Duration = .milliseconds(500)
    /// The grammar the merge window asks off the main actor. Behind a lock so a pack reload can swap it; the mode
    /// machine holds its own copy, swapped with it on the main actor.
    private let mergeGrammar: OSAllocatedUnfairLock<CommandGrammar>
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
                observer: ScreenObserver? = nil, taskRunner: TaskRunner? = nil, harness: (any DesktopHarness)? = nil,
                commandLog: CommandLogStore? = nil) {
        self.config = config
        self.commandLog = commandLog
        self.attention = config.attentionGate
        self.transcriber = transcriber
        let observer = observer ?? ScreenObserver(ax: ax, maxElements: config.observedElementCap, harness: harness,
                                                  snapshotTimeoutMs: config.agentDesktopSnapshotMs)
        self.runner = taskRunner ?? resolver.map {
            TaskRunner(config: config, resolver: $0, executor: executor, observer: observer, overlay: overlay, harness: harness,
                       screenshots: config.visionEnabled ? WindowScreenshotter(ax: ax) : nil)
        }
        self.executor = executor
        executor.useRewriter(config: config)
        self.overlay = overlay
        self.ax = ax
        self.harness = harness
        let grammar = CommandGrammar(config: config.grammarConfig)
        self.mergeGrammar = OSAllocatedUnfairLock(initialState: grammar)
        self.modeMachine = ModeMachine(grammar: grammar, attention: config.attentionGate, macros: config.macros)
        executor.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.modeMachine.apply(mode: mode)
            self.publishStatus()
        }
    }

    /// Looks pack phrases up in `packs` from the next utterance on. An utterance already being routed finishes on the
    /// old set: routing runs on the main actor, as this does.
    public func setPacks(_ packs: PackSet) {
        let grammar = mergeGrammar.withLock { state -> CommandGrammar in
            state = state.with(packs: packs)
            return state
        }
        modeMachine.use(grammar: grammar)
    }

    /// Moves new tasks to another backend from the next command on, without stopping the microphone. Builds a runner
    /// like `init` does (screenshots follow `config.visionEnabled`); a task already running finishes on its own
    /// runner, and a command held behind it goes to the new one. Other settings in `config` are not re-read.
    public func switchBackend(config: AppConfig, resolver: any IntentResolving, observer: ScreenObserver) {
        executor.useRewriter(config: config)
        replaceRunner(TaskRunner(config: config, resolver: resolver, executor: executor, observer: observer,
                                 overlay: overlay, harness: harness,
                                 screenshots: config.visionEnabled ? WindowScreenshotter(ax: ax) : nil))
    }

    /// Takes `new` at once when no task is running; otherwise holds it (the newest wins) until the task loop is between runs.
    func replaceRunner(_ new: TaskRunner) {
        lastTask = nil
        runnerGeneration += 1
        if activeTask == nil { runner = new; pendingRunner = nil } else { pendingRunner = new }
    }

    /// Called only where no runner is running: between runs inside the task loop.
    private func applyPendingRunner() {
        if let pendingRunner { runner = pendingRunner }
        pendingRunner = nil
    }

    /// What the grammar makes of `phrase`. Whether a text field has focus matters only to the edits that name words in
    /// the field, so the front app is asked (`textFocused`, an Accessibility read) only when it changes the answer.
    nonisolated static func parsed(_ phrase: String, grammar: CommandGrammar, frontmost: String?,
                                   textFocused: @Sendable () -> Bool) -> [Action]? {
        let plain = grammar.parse(phrase, frontmost: frontmost)
        let ifFocused = grammar.parse(phrase, frontmost: frontmost, textFocused: true)
        return plain == ifFocused || !textFocused() ? plain : ifFocused
    }

    /// Skips the merge window: a complete grammar command in command mode, a stop phrase in any mode, and the
    /// dictation commands (escape phrases, "scratch that", "delete word", text edits) in dictation mode. Internal so tests build their MergeBuffer the same way.
    /// With the attention word on, a command mode grammar command counts only after the word ("computer, go back").
    nonisolated static func isComplete(_ transcript: String, mode: Mode, grammar: CommandGrammar, macros: Macros = Macros(),
                                       attention: AttentionGate = .off, frontmost: String? = nil,
                                       textFocused: @Sendable () -> Bool = { false }) -> Bool {
        if attention.isStop(transcript) { return true }
        switch mode {
        case .command:
            // "spell" always waits the merge window: a pause mid-spelling must not type half and send the rest to the model.
            func complete(_ phrase: String) -> Bool {
                CommandGrammar.normalize(phrase).first != "spell"
                    && (parsed(phrase, grammar: grammar, frontmost: frontmost, textFocused: textFocused) != nil
                        || macros.match(phrase) != nil)   // a macro name is whole, like a grammar command
            }
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
                                              attention: AttentionGate = .off, frontmost: String? = nil,
                                              textFocused: @Sendable () -> Bool = { false }) -> Bool {
        var phrase = transcript
        if case .addressed(let rest) = attention.check(transcript) { phrase = rest }
        return parsed(phrase, grammar: grammar, frontmost: frontmost, textFocused: textFocused)?.carriesSpokenText ?? true
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
    /// segment. Internal so tests can drive it with a fake transcriber. Every transcript goes through `vocabulary`
    /// before anything else sees it, except a stop or a mode phrase, which is passed on as heard (`Vocabulary.rewrite`).
    nonisolated static func runASR(_ jobs: AsyncStream<ASRJob>, transcriber: any Transcribing, merge: MergeBuffer,
                                   vocabulary: Vocabulary = Vocabulary(), attention: AttentionGate = .off) async {
        func corrected(_ heard: String) -> String { vocabulary.rewrite(heard, attention: attention) }
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
                    let text = corrected(try await transcriber.transcribe(audio))
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
                    let text = corrected(try await transcriber.transcribe(audio))
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

        let mergeGrammar = self.mergeGrammar
        let attention = self.attention
        let vocabulary = config.vocabulary
        let macros = config.macros
        let front = FrontmostApp.shared   // a pack phrase closes the merge window early, like a global one
        let ax = self.ax   // asked only for a text edit that names words in the field
        let merge = MergeBuffer(
            merger: UtteranceMerger(windowMs: config.mergeWindowMs, unfinishedWindowMs: config.mergeWindowUnfinishedMs),
            gate: attention,
            isComplete: { Self.isComplete($0, mode: $1, grammar: mergeGrammar.withLock { $0 }, macros: macros, attention: attention, frontmost: front.bundleID,
                                          textFocused: { ax.isTextFocused() }) },
            carriesSpokenText: { Self.carriesSpokenText($0, grammar: mergeGrammar.withLock { $0 }, attention: attention, frontmost: front.bundleID,
                                                        textFocused: { ax.isTextFocused() }) },
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
            await Self.runASR(utterances, transcriber: transcriber, merge: merge, vocabulary: vocabulary, attention: attention)
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
        lastTask = nil
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
    /// other reply only stops the task); while it waits for the answer to a question, the next addressed words are
    /// the answer; anything else replaces the held job.
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
        } else if let runner, runner.awaitedAnswer == .question {
            // A question the model asked: stray speech is dropped and the question keeps waiting; an addressed
            // utterance is the answer, without the attention word.
            if isUnaddressed(job.transcript) {
                if job.shown { overlay.report(job.id, text: job.transcript, status: .ignored("")) }
                PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "ignore(not addressed)", detail: "ignore(not addressed)")
            } else {
                var reply = job.transcript
                if case .addressed(let rest) = attention.check(reply) { reply = rest }
                runner.answer(reply)
                overlay.report(job.id, text: job.transcript, status: .done(reply))
                PipelineLog.utterance(trace: job.trace, transcript: job.transcript, outcome: "answer", detail: "answer")
            }
        } else if let runner, runner.awaitedAnswer == .confirm {
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
        let modeBefore = modeMachine.mode
        // Edits that name words in the field, and rewrites of the selection, need to know a text field has focus; any
        // other phrase never asks. Dictation types rewrite phrases as words, so only command mode asks for those.
        var textFocused = false
        if ModeMachine.namesTextEdit(text, attention: attention)
            || (modeBefore == .command && ModeMachine.namesRewrite(text, attention: attention)) {
            let ax = self.ax
            textFocused = await Task.detached { ax.isTextFocused() }.value
        }
        var routing = modeMachine.route(text, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                        textFocused: textFocused)
        // Words typed in dictation mode are typing, not a command; its own commands ("stop dictating") are commands.
        // A phrase edit with no text field is typed as words, so it is typing too.
        var isCommand = modeBefore != .dictation || ModeMachine.isDictationCommand(text, attention: attention)
        if modeBefore == .dictation, case .execute(let actions) = routing, case .typeText = actions.first { isCommand = false }
        // A stop phrase with no task running must not start one (held jobs never get here: busy() intercepts them).
        if case .resolveWithLLM(let phrase) = routing, StopWords.isStop(phrase) { routing = .ignore(reason: "stop") }
        if modeMachine.mode != modeBefore { lastTask = nil }   // a mode switch or sleep ends the conversation
        var outcome = PipelineText.summary(routing)                    // public: kinds only
        var detail = PipelineText.summary(routing, detailed: true)     // private: with payloads

        switch routing {
        case .macro(let macro):
            overlay.report(job.id, text: text, status: .heard)
            guard canExecute else {
                overlay.report(job.id, text: text, status: .dropped(PipelineText.cancelled))
                outcome += " (cancelled)"; detail += " (cancelled)"; break
            }
            return PendingTask(id: job.id, goal: macro.name, transcript: text, trace: trace, macro: macro)
        case .ignore(let reason):
            // Nothing on the board (this also keeps sleep silent), unless the merge window already put the words
            // there: that row must not stay "listening".
            if job.shown { overlay.report(job.id, text: text, status: .ignored(reason == "sleeping" ? "asleep" : "")) }
        case .reject(let message):
            overlay.report(job.id, text: text, status: .failed(message))
            recordCommand(CommandLogEntry(date: Date(), phrase: text, resolver: .grammar, steps: [],
                                          outcome: .failed(message), durationMs: 0))
        case .execute(let actions):
            overlay.report(job.id, text: text, status: .heard)
            guard canExecute else {
                overlay.report(job.id, text: text, status: .dropped(PipelineText.cancelled))
                outcome += " (cancelled)"; detail += " (cancelled)"; break
            }
            // A rewrite waits on the model: it runs in the task slot, where a spoken stop can cancel it.
            if actions.count == 1, case .rewriteText(let how) = actions[0] {
                return PendingTask(id: job.id, goal: "", transcript: text, trace: trace, rewrite: how)
            }
            let began = Date(), clock = ContinuousClock.now
            let failure = await executor.execute(actions)
            // An edit moved the caret or the text: "scratch that" no longer matches the screen. Dictation that an edit
            // fell back to typing is the exception, the record is right.
            let typedAsWords = executor.editTypedOtherwise
            if actions.contains(where: { if case .editText = $0 { true } else { false } }), !typedAsWords {
                modeMachine.forgetDictationRecord()
            }
            // Dictation typed as the fallback is the speaker's words, not a command: it never goes in the command log.
            if isCommand, !typedAsWords {
                recordCommand(.grammar(date: began, phrase: text, action: PipelineText.describe(actions), failure: failure,
                                       durationMs: CommandLogEntry.milliseconds(clock.duration(to: .now))))
            }
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
                let hint = noResolverHint()
                overlay.report(job.id, text: text, status: .ignored(hint))
                recordCommand(CommandLogEntry(date: Date(), phrase: text, resolver: .none, steps: [],
                                              outcome: .ignored(hint), durationMs: 0))
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
        guard runner != nil || first.rewrite != nil || first.macro != nil else { return }
        activeTask = Task { [self] in
            var next: PendingTask? = first
            while let pending = next {
                next = nil
                applyPendingRunner()
                if let how = pending.rewrite {
                    await runRewrite(pending, how)
                } else if let macro = pending.macro {
                    await runMacro(macro, pending: pending)
                } else if let runner {
                    await runTask(pending, runner: runner)
                } else { break }
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

    /// Runs a rewrite of the selection and shows how it ended on its row. The command log and the logs get counts only:
    /// the selected text and the answer are model input and output the user has not read.
    private func runRewrite(_ pending: PendingTask, _ how: RewriteInstruction) async {
        let id = pending.id, text = pending.transcript
        executor.onRewriteStart = { [weak self] in self?.overlay.report(id, text: text, status: .running(PipelineText.rewriting)) }
        let began = Date(), clock = ContinuousClock.now
        let failure = await executor.execute([.rewriteText(how)])
        executor.onRewriteStart = nil
        let report = executor.takeRewrite()
        let durationMs = CommandLogEntry.milliseconds(clock.duration(to: .now))
        let result: CommandLogEntry.Outcome
        let kind: String
        if failure == ActionExecutor.cancelled {
            overlay.report(id, text: text, status: .stopped(PipelineText.stopped))
            result = .stopped; kind = "stopped"
        } else if let failure {
            overlay.report(id, text: text, status: .failed(failure))
            result = .failed(failure); kind = "failed"
        } else {
            overlay.report(id, text: text, status: .done(report?.preview ?? ""))
            result = .done; kind = "done"
        }
        let action = report.map { "rewrote \($0.from) → \($0.to) characters" } ?? "rewrite \(how.kind)"
        recordCommand(CommandLogEntry(date: began, phrase: text, resolver: .grammar,
                                      steps: [.init(number: 1, action: action, result: result, startedAt: began, durationMs: durationMs)],
                                      outcome: result, durationMs: durationMs))
        var trace = pending.trace
        trace.actionsDone = .now
        PipelineLog.utterance(trace: trace, transcript: text, outcome: "rewrite(\(how.kind), \(kind))", detail: "rewrite(\(how.kind), \(kind)) \(action)")
        publishStatus()
    }


    /// `row` is the words on the prompt's row when they are not `pending.transcript` (a macro step: the row shows the
    /// macro's name, the log the step); `relabel` rewrites each line the runner reports, nil hides it.
    @discardableResult
    private func runTask(_ pending: PendingTask, runner: TaskRunner, row: String? = nil,
                         relabel: @escaping (PromptStatus) -> PromptStatus? = { $0 }) async -> TaskOutcome {
        // The runner's step and finish lines go on this prompt's row.
        let id = pending.id, text = row ?? pending.transcript
        runner.onStatus = { [weak self] status in
            if let shown = relabel(status) { self?.overlay.report(id, text: text, status: shown) }
        }
        runner.onTrail = { [weak self] trail in self?.overlay.report(id, trail: trail) }
        let kind = resolverKind
        _ = await runner.takeUsage()   // a cancelled earlier task's calls must not count here
        let began = Date(), clock = ContinuousClock.now
        let earlier = FollowUp.memory(lastTask, endedAt: lastTaskEnded, now: .now, windowMs: config.followUpWindowMs, goal: pending.goal)
        let generation = runnerGeneration, stops = stopGeneration
        let outcome = await runner.run(goal: pending.goal, mode: modeMachine.mode, earlier: earlier)
        if generation != runnerGeneration || stops != stopGeneration {
            lastTask = nil   // a backend switch or a pause during the run ends the conversation
        } else if let kept = runner.lastTask {
            lastTask = kept; lastTaskEnded = .now
        } else if earlier == nil {
            lastTask = nil   // a new request that was ignored or failed replaces the old memory; a follow-up leaves it (and its end time)
        }
        recordTask(pending, runner: runner, outcome: outcome, kind: kind, began: began,
                   durationMs: CommandLogEntry.milliseconds(clock.duration(to: .now)), usage: await runner.takeUsage())
        runner.onStatus = nil
        runner.onTrail = nil
        let sessionUsage = ClaudeUsageMeter.shared.total
        if kind == .claude, sessionUsage.calls > 0 { PipelineLog.info("claude: session \(sessionUsage.logFragment)") }
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
        return outcome
    }

    /// Runs a macro's steps in order on one row, inside `activeTask`: a stop reaches it through `busy()` like any task.
    /// The first step that fails, is not understood, changes the mode or is stopped ends it.
    private func runMacro(_ macro: Macro, pending: PendingTask) async {
        let id = pending.id, text = pending.transcript, total = macro.steps.count
        func at(_ n: Int, _ detail: String) -> String { "step \(n) of \(total) · \(detail)" }
        var result = PromptStatus.done("done · \(total) steps")
        for (index, step) in macro.steps.enumerated() {
            let n = index + 1
            guard canExecute else { result = .stopped("stopped at step \(n) of \(total)"); break }
            overlay.report(id, text: text, status: .running(at(n, step)))
            var textFocused = false
            if ModeMachine.namesTextEdit(step) {
                let ax = self.ax
                textFocused = await Task.detached { ax.isTextFocused() }.value
            }
            let phrase = "\(macro.name) › \(step)"
            let routing = modeMachine.routeStep(step, frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                                textFocused: textFocused)
            var failure: String?
            switch routing {
            case .execute(let actions):
                let began = Date(), clock = ContinuousClock.now
                failure = await executor.execute(actions)
                recordCommand(.grammar(date: began, phrase: phrase, action: PipelineText.describe(actions), failure: failure,
                                       durationMs: CommandLogEntry.milliseconds(clock.duration(to: .now))))
                _ = executor.takeReadings()   // a reading ("is it playing") belongs to this step, not the next spoken command
                if failure == nil, n < total { try? await Task.sleep(for: macroStepPause) }
            case .resolveWithLLM(let goal):
                if let runner {
                    var task = pending
                    task.goal = goal; task.transcript = phrase; task.macro = nil
                    let outcome = await runTask(task, runner: runner, row: text) { status in
                        if case .running(let detail) = status { .running(at(n, detail)) } else { nil }
                    }
                    switch outcome {
                    case .done: break
                    case .stopped: failure = ActionExecutor.cancelled
                    case .stuck(let why), .failed(let why): failure = why
                    case .ignored: failure = PipelineText.didntCatch
                    }
                } else {
                    failure = noResolverHint()
                }
            case .reject(let message): failure = message
            case .ignore, .macro: failure = PipelineText.didntCatch
            }
            if let failure {
                let ended = failure == ActionExecutor.cancelled || !canExecute
                result = ended ? .stopped("stopped at step \(n) of \(total)") : .failed(at(n, failure))
                break
            }
            if modeMachine.mode != .command { lastTask = nil; result = .failed(at(n, "changed mode")); break }
        }
        overlay.report(id, text: text, status: result)
        let kind: String
        switch result {
        case .done: kind = "done"
        case .stopped: kind = "stopped"
        default: kind = "failed"
        }
        var trace = pending.trace
        trace.actionsDone = .now
        PipelineLog.utterance(trace: trace, transcript: text, outcome: "macro(\(kind))", detail: "macro(\(result.text))")
        publishStatus()
    }

    private func recordCommand(_ entry: CommandLogEntry) {
        commandLog?.append(entry)
    }

    /// Writes the finished task into the command log: its steps with times, how it ended and its Claude tokens.
    /// The file write is not awaited.
    private func recordTask(_ pending: PendingTask, runner: TaskRunner, outcome: TaskOutcome,
                            kind: CommandLogEntry.Resolver, began: Date, durationMs: Int, usage: [ClaudeUsage]) {
        guard let commandLog else { return }
        let ended: CommandLogEntry.Outcome
        switch outcome {
        case .done: ended = .done
        case .stuck(let why), .failed(let why): ended = .failed(why)
        case .ignored: ended = .ignored("")
        case .stopped: ended = .stopped
        }
        commandLog.append(.fromTrail(runner.currentTrail, date: began, phrase: pending.transcript, resolver: kind,
                                     outcome: ended, durationMs: durationMs, usage: .sum(usage),
                                     endedAt: Date()))
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
