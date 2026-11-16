import AVFoundation
import Foundation
import os
import NoHandsCore

/// Says a line out loud (NH-60). The pipeline decides what and when; this only plays and cuts.
@MainActor public protocol FeedbackSpeaking: AnyObject {
    /// The line being said or just said, with when it started and ended; nil before the first. The echo filter
    /// compares transcripts with it.
    var current: SpokenLine? { get }
    /// Says `text`, replacing the line playing (newest wins; nothing queues).
    func speak(_ text: String)
    /// Stops the line playing, if any.
    func cut()
}

extension Action {
    /// The action puts text the user did not say in front of the task (or into the field), so a finish line that follows
    /// it may repeat that text.
    var readsText: Bool {
        switch self {
        case .readClipboard, .readPage, .readValue, .readNotifications, .rewriteText: true
        default: false
        }
    }
}

/// Speaks with the system voices, in the user's Spoken Content voice and rate. With echo cancellation running, the
/// speech is played through the capture engine, so voice processing has it as its echo reference and removes it
/// before VAD; otherwise it goes to the system output with `AVSpeechSynthesizer.speak`.
@MainActor public final class FeedbackSpeaker: NSObject, FeedbackSpeaking, AVSpeechSynthesizerDelegate {
    /// A line that never reports its end (a voice that yields no audio) is treated as finished after this long.
    static let watchdog: Duration = .seconds(45)

    private let synth = AVSpeechSynthesizer()
    /// The capture to play through, asked at each line; nil (or one without echo cancellation) uses the system output.
    private let capture: @MainActor () -> MicrophoneCapture?
    public private(set) var current: SpokenLine?
    private var utterance: AVSpeechUtterance?
    private var tracker: PlaybackTracker?
    private var timeout: Task<Void, Never>?

    public init(capture: @escaping @MainActor () -> MicrophoneCapture?) {
        self.capture = capture
        super.init()
        synth.delegate = self
    }

    public func speak(_ text: String) {
        cut()
        let next = AVSpeechUtterance(string: text)
        next.prefersAssistiveTechnologySettings = true
        utterance = next
        current = SpokenLine(text: text, start: .now)
        let id = ObjectIdentifier(next)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.watchdog)
            if !Task.isCancelled { self?.finished(id) }
        }
        if let mic = capture(), mic.echoCancellationActive {
            let tracker = PlaybackTracker { [weak self] in Task { @MainActor in self?.finished(id) } }
            self.tracker = tracker
            Self.render(next, with: synth, into: mic, tracker: tracker)
        } else {
            synth.speak(next)
        }
    }

    public func cut() {
        timeout?.cancel()
        timeout = nil
        tracker?.cancel()
        tracker = nil
        utterance = nil
        synth.stopSpeaking(at: .immediate)
        capture()?.cancelPlayback()
        if current?.end == nil { current?.end = .now }
    }

    private func finished(_ id: ObjectIdentifier) {
        guard let utterance, ObjectIdentifier(utterance) == id else { return }
        timeout?.cancel()
        timeout = nil
        self.utterance = nil
        if current?.end == nil { current?.end = .now }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finished(id) }
    }

    /// Synthesizes `utterance` into buffers and plays them through `capture`. Nonisolated on purpose: AVFoundation
    /// calls the buffer callback on its own queue, and a closure made on the main actor would trap there.
    nonisolated private static func render(_ utterance: AVSpeechUtterance, with synth: AVSpeechSynthesizer,
                                           into capture: MicrophoneCapture, tracker: PlaybackTracker) {
        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength == 0 { tracker.synthesisDone(); return }   // an empty buffer ends the speech
            guard tracker.begin() else { return }                         // cut while synthesizing
            capture.play(pcm) { tracker.bufferDone() }
        }
    }
}

/// Counts the buffers of one line that are still playing, and reports once when synthesis is done and all have played.
final class PlaybackTracker: Sendable {
    private struct State { var pending = 0; var synthesized = false; var cancelled = false; var reported = false }
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let onEnd: @Sendable () -> Void

    init(onEnd: @escaping @Sendable () -> Void) { self.onEnd = onEnd }

    /// False when the line was cut: the buffer must not be played.
    func begin() -> Bool { state.withLock { if $0.cancelled { return false }; $0.pending += 1; return true } }
    func bufferDone() { change { $0.pending -= 1 } }
    func synthesisDone() { change { $0.synthesized = true } }
    func cancel() { state.withLock { $0.cancelled = true } }

    private func change(_ body: @Sendable (inout State) -> Void) {
        let report = state.withLock { s -> Bool in
            body(&s)
            guard s.synthesized, s.pending <= 0, !s.cancelled, !s.reported else { return false }
            s.reported = true
            return true
        }
        if report { onEnd() }
    }
}
