import Foundation
import NoHandsCore

/// mic -> VAD -> assembler -> (bounded queue, newest 2) -> ASR -> (serial job stream) -> ModeMachine -> executor / resolver.
///
/// Audio, VAD and ASR run off the main actor. Everything that touches the executor, overlay or mode machine
/// runs in ONE main-actor consumer task, so utterances are executed strictly one after another.
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

    private let config: AppConfig
    private let transcriber: any Transcribing
    private let resolver: (any IntentResolving)?
    private let executor: ActionExecutor
    private let overlay: OverlayController
    private let ax: any ElementProviding

    private var modeMachine: ModeMachine
    private var vad: VoiceActivity?
    private var mic: MicrophoneCapture?
    private var tasks: [Task<Void, Never>] = []
    private var consumer: Task<Void, Never>?
    private var starting = false
    private var warmedUp = false
    private var llmOffShown = false
    private var lastTranscript = ""

    public var isRunning: Bool { mic != nil }
    public var mode: Mode { modeMachine.mode }

    public init(config: AppConfig, transcriber: any Transcribing, resolver: (any IntentResolving)?,
                executor: ActionExecutor, overlay: OverlayController, ax: any ElementProviding = AXQuery()) {
        self.config = config
        self.transcriber = transcriber
        self.resolver = resolver
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

    /// Loads VAD, warms up ASR (first call only) and starts the microphone.
    public func start() async throws {
        guard mic == nil, !starting else { return }
        starting = true
        defer { starting = false }

        // A consumer from a previous session may still be executing an utterance; let it finish first so
        // execution stays strictly serialized across pause/resume.
        await consumer?.value
        consumer = nil

        if vad == nil { vad = try await VoiceActivity(silenceMs: config.silenceMs) }
        let vad = self.vad!
        await vad.reset()
        if !warmedUp { warmedUp = await warmUp() }

        let (chunks, chunkCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        // At most 2 pending utterances; when full the OLDEST is dropped.
        let (utterances, uttCont) = AsyncStream<(samples: [Float], at: ContinuousClock.Instant)>
            .makeStream(bufferingPolicy: .bufferingNewest(2))
        let (jobs, jobCont) = AsyncStream<Job>.makeStream(bufferingPolicy: .bufferingNewest(2))

        let capture = try MicrophoneCapture()
        capture.onEvent = { [weak self] event in
            if case .failed(let message) = event {
                PipelineLog.error("[mic] \(message)")
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
        let overlay = self.overlay

        let vadTask = Task.detached {
            var assembler = UtteranceAssembler()
            for await chunk in chunks {
                do {
                    let ev = try await vad.process(chunk)
                    if let utterance = assembler.push(chunk, event: ev) {
                        if case .dropped = uttCont.yield((utterance, .now)) {
                            PipelineLog.warning("asr backlog: dropped oldest pending utterance")
                        }
                    }
                } catch {
                    PipelineLog.error("vad error (state reset): \(error)")
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
                    if !text.isEmpty {
                        if case .dropped = jobCont.yield(Job(transcript: text, trace: trace)) {
                            PipelineLog.warning("busy: dropped oldest queued utterance")
                            await MainActor.run { overlay.showHUD("skipped (busy)") }
                        }
                    }
                } catch {
                    PipelineLog.error("asr error (utterance skipped): \(error)")
                }
            }
            jobCont.finish()
        }
        // The single serial consumer: each job is fully handled (including awaiting the executor) before the next.
        let execTask = Task { @MainActor [weak self] in
            for await job in jobs {
                guard !Task.isCancelled, let self else { break }
                await self.handle(job)
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
        mic?.stop()
        mic = nil
        for t in tasks { t.cancel() }
        tasks = []
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
            PipelineLog.error("[asr] warm-up failed: \(error)")
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

    private func publishStatus() { onStatus?(modeMachine.mode, lastTranscript) }

    private func handle(_ job: Job) async {
        var trace = job.trace
        let text = job.transcript
        if let spoke = trace.speechEnd, StaleJobPolicy.isStale(age: spoke.duration(to: .now)) {
            PipelineLog.warning("busy: skipped stale utterance (older than 8 s)")
            overlay.showHUD("skipped (busy)")
            return
        }
        lastTranscript = text
        let routing = modeMachine.route(text)
        var outcome = PipelineText.summary(routing)

        switch routing {
        case .ignore:
            break   // nothing on the HUD (this also keeps sleep silent)
        case .execute(let actions):
            overlay.showHUD(text)
            if let failure = await executor.execute(actions) { outcome += " FAILED(\(failure))" }
        case .resolveWithLLM(let phrase):
            overlay.showHUD(text)
            outcome += await resolve(phrase)
        }

        trace.actionsDone = .now
        PipelineLog.utterance(trace: trace, transcript: text, outcome: outcome)
        publishStatus()
    }

    /// Returns a suffix for the log line.
    private func resolve(_ phrase: String) async -> String {
        guard let resolver else {
            if llmOffShown {
                overlay.showHUD(PipelineText.didntCatch)
            } else {
                llmOffShown = true
                overlay.showHUD(PipelineText.llmOff)
            }
            return " (no resolver)"
        }
        let context = IntentContextBuilder.make(elements: ax, mode: modeMachine.mode)
        do {
            let actions = try await resolver.resolve(phrase, context: context)
            guard !actions.isEmpty else {
                overlay.showHUD(PipelineText.didntCatch)
                return " -> no actions"
            }
            var suffix = " -> \(PipelineText.describe(actions))"
            if let failure = await executor.execute(actions) { suffix += " FAILED(\(failure))" }
            return suffix
        } catch let error as IntentError {
            if let message = PipelineText.hud(for: error) { overlay.showHUD(message) }
            return " -> error(\(Self.label(error)))"
        } catch {
            overlay.showHUD(PipelineText.didntCatch)
            return " -> error"
        }
    }

    /// Error kind only; never the associated payloads (no request details in logs).
    private static func label(_ e: IntentError) -> String {
        switch e {
        case .noAPIKey: "noAPIKey"
        case .network: "network"
        case .http(let c, _): "http \(c)"
        case .decode: "decode"
        case .timeout: "timeout"
        case .cancelled: "cancelled"
        }
    }
}
