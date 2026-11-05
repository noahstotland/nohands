import Foundation
import NoHandsCore

/// Sits between ASR and execution. A finished transcript is held for a short window; if the VAD reports
/// speech again inside it, the next transcript is appended and the window restarts, so a mid-command pause
/// yields one merged request. Grammar commands that are not left hanging are released immediately; a stop phrase
/// (and, in dictation, "stop dictating" / "command mode") is never merged and always released immediately.
actor MergeBuffer {
    struct Pending: Sendable {
        var transcript: String
        var trace: LatencyTrace
    }

    private let merger: UtteranceMerger
    private let gate: AttentionGate
    private let isComplete: @Sendable (String, Mode) -> Bool
    private let emit: @Sendable (String, LatencyTrace) -> Void
    private let onHold: @Sendable (String) -> Void
    private var pending: Pending?
    private var speechActive = false
    private var mode: Mode = .command
    private var timer: Task<Void, Never>?
    private var generation = 0
    /// If speech started but no transcript or abandon notice ever arrives, flush anyway.
    static let safetyTimeout: Duration = .seconds(20)

    init(merger: UtteranceMerger,
         gate: AttentionGate = .off,
         isComplete: @escaping @Sendable (String, Mode) -> Bool,
         onHold: @escaping @Sendable (String) -> Void,
         emit: @escaping @Sendable (String, LatencyTrace) -> Void) {
        self.merger = merger
        self.gate = gate
        self.isComplete = isComplete
        self.onHold = onHold
        self.emit = emit
    }

    func set(mode: Mode) { self.mode = mode }

    func transcript(_ text: String, trace: LatencyTrace) {
        speechActive = false
        // A stop phrase or a dictation command is never merged: it must reach the pipeline on its own, at once.
        if gate.isStop(text) {
            // In command mode a stop also cancels what was still being said; in dictation the words already
            // spoken are kept (typed) before the stop.
            if mode == .dictation { flush() } else { discardPending() }
            pending = Pending(transcript: text, trace: trace)
            flush()
            return
        }
        if mode == .dictation && ModeMachine.isDictationCommand(text, attention: gate) {
            flush()
            pending = Pending(transcript: text, trace: trace)
            flush()
            return
        }
        // With the attention word on, stray speech is never merged into a command that addresses it.
        if gated, pending != nil {
            switch gate.check(text) {
            case .addressed, .wordOnly: flush()
            case .notAddressed, .off: break
            }
        }
        var next = Pending(transcript: text, trace: trace)
        if let p = pending { next.transcript = UtteranceMerger.merge(p.transcript, text) }
        pending = next
        let hold = holdDuration(for: next.transcript)
        if hold == .zero { flush(); return }
        // Stray speech is held (it may still be the start of "computer …") but shown nowhere.
        if !(gated && gate.check(next.transcript) == .notAddressed) { onHold(next.transcript) }
        schedule(after: hold)
    }

    /// The VAD saw speech begin: whatever is pending waits for that speech's transcript.
    func speechStarted() {
        guard pending != nil else { return }
        speechActive = true
        schedule(after: Self.safetyTimeout)
    }

    /// Speech ended without a usable transcript (too short, silent, ASR error): resume the normal window.
    func speechAbandoned() {
        guard speechActive, let p = pending else { return }
        speechActive = false
        let hold = holdDuration(for: p.transcript)
        if hold == .zero { flush() } else { schedule(after: hold) }
    }

    func reset() { discardPending() }

    /// Command mode with the attention word on.
    private var gated: Bool { gate.isOn && mode == .command }

    private func holdDuration(for transcript: String) -> Duration {
        // The word alone waits like a dangling word, so "computer … go back" said in two breaths is one command.
        // The merger's rules (dangling last word, a leading "spell") apply to what follows the word.
        var phrase = transcript
        if gated {
            switch gate.check(transcript) {
            case .wordOnly: return .milliseconds(merger.unfinishedWindowMs)
            case .addressed(let rest): phrase = rest
            case .notAddressed, .off: break
            }
        }
        return merger.hold(for: phrase, isComplete: isComplete(transcript, mode))
    }

    private func discardPending() {
        generation += 1
        timer?.cancel()
        timer = nil
        pending = nil
        speechActive = false
    }

    private func schedule(after delay: Duration) {
        generation += 1
        let gen = generation
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.fire(gen)
        }
    }

    private func fire(_ gen: Int) {
        guard gen == generation else { return }
        flush()
    }

    private func flush() {
        generation += 1
        timer?.cancel()
        timer = nil
        speechActive = false
        guard let p = pending else { return }
        pending = nil
        emit(p.transcript, p.trace)
    }
}
