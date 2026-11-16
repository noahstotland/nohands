import AVFoundation
import Foundation
import NoHandsCore

public enum MicrophoneError: Error { case noInputFormat, converterUnavailable }

public enum MicrophoneEvent: Sendable, Equatable {
    case started
    /// The audio configuration changed (device switch, sample-rate change) and capture was rebuilt.
    case restarted
    case failed(String)
    /// Reported once per `start()` after the first successful start: whether voice processing (echo
    /// cancellation) is on. False when the config turned it off or macOS refused it.
    case echoCancellation(Bool)
}

/// Captures the default input device as 16 kHz mono Float32 in exact 4096-sample chunks.
///
/// Threading: the AVAudioEngine tap runs on a realtime audio thread. There we only copy the raw buffer
/// and hand it to a private serial queue; format conversion, 4096-sample chunking, `onChunk` and
/// `onEvent` all run on that queue, never on the audio thread. On AVAudioEngineConfigurationChange
/// the tap is rebuilt for the new input format and the engine restarted.
/// Microphone permission is NOT checked here.
public final class MicrophoneCapture: @unchecked Sendable {
    public static let chunkSize = 4096

    /// Called on the capture queue.
    public var onEvent: (@Sendable (MicrophoneEvent) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return _onEvent }
        set { lock.lock(); _onEvent = newValue; lock.unlock() }
    }

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "nohands.mic.chunks", qos: .userInteractive)
    private let outFormat: AVAudioFormat
    private let lock = NSLock()
    private let echoCancellation: Bool
    private var _onEvent: (@Sendable (MicrophoneEvent) -> Void)?
    private var running = false                              // guarded by lock
    private var generation = 0                               // guarded by lock; bumped by every start/stop
    private var observer: NSObjectProtocol?                  // guarded by lock
    private var echoUnavailable = false                      // guarded by lock; set once macOS refuses voice processing
    private var echoActive = false                           // guarded by lock; voice processing is on for the running engine
    // Playback (NH-60), confined to `playbackQueue`:
    private let playbackQueue = DispatchQueue(label: "nohands.mic.playback", qos: .userInitiated)
    private var player: AVAudioPlayerNode?
    /// Serializes every change to the engine's graph (the rebuild in `installTapAndStart`, the player's attach and
    /// connect, its detach), which run on different threads. Never held while waiting on another queue.
    private let graphLock = NSLock()
    private var playbackConverters: [AVAudioFormat: AVAudioConverter] = [:]
    private static var playbackFormat: AVAudioFormat? { AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1) }
    // Queue-confined:
    private var onChunk: (@Sendable ([Float]) -> Void)?
    private var converter: AVAudioConverter?
    private var pending: [Float] = []

    public init(echoCancellation: Bool = true) throws {
        self.echoCancellation = echoCancellation
        guard let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)
        else { throw MicrophoneError.converterUnavailable }
        outFormat = f
    }

    /// 16 kHz mono Float32 chunks of exactly 4096 samples (VadManager.chunkSize), delivered on a background queue.
    public func start(_ onChunk: @escaping @Sendable ([Float]) -> Void) throws {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        generation += 1
        let gen = generation
        lock.unlock()
        queue.sync { self.onChunk = onChunk; self.pending.removeAll(); self.converter = nil }
        do {
            try installTapAndStart(generation: gen)
        } catch {
            lock.lock()
            if generation == gen { running = false }
            lock.unlock()
            throw error
        }
        // Register the observer only if stop() has not run meanwhile (checked under the same lock stop() uses).
        lock.lock()
        guard running, generation == gen else { lock.unlock(); return }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in self?.handleConfigurationChange(generation: gen, failures: 0) }
        }
        lock.unlock()
        emit(.started)
        // Once per start() session, not per configuration-change rebuild (those do not pass through here).
        emit(.echoCancellation(engine.inputNode.isVoiceProcessingEnabled))
    }

    public func stop() {
        lock.lock()
        let was = running
        running = false
        generation += 1
        let token = observer
        observer = nil
        lock.unlock()
        guard was else { return }
        if let token { NotificationCenter.default.removeObserver(token) }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        setEchoActive(false)
        resetPlayback()
        queue.sync { self.onChunk = nil; self.pending.removeAll(); self.converter = nil }
    }

    /// True while the engine runs with voice processing on, so audio played with `play` is the echo reference and is
    /// removed from the microphone before VAD.
    public var echoCancellationActive: Bool { lock.lock(); defer { lock.unlock() }; return running && echoActive }

    private func setEchoActive(_ on: Bool) { lock.lock(); echoActive = on; lock.unlock() }

    /// Plays `buffer` (any PCM format) through the capture engine's output, after anything already queued. Does nothing
    /// when the engine is not running. `completion` runs once the buffer has played or been cancelled; it also runs
    /// when nothing could be played. The player node is attached to the main mixer on first use.
    public func play(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) {
        let box = BufferBox(buffer)
        playbackQueue.async { [self] in
            guard isRunning, engine.isRunning, let converted = convertForPlayback(box.buffer) else { completion(); return }
            let node = attachedPlayer()
            node.scheduleBuffer(converted, completionCallbackType: .dataPlayedBack) { _ in completion() }
            if !node.isPlaying { node.play() }
        }
    }

    /// Stops what `play` is saying and drops what is queued; each buffer's completion runs.
    public func cancelPlayback() {
        playbackQueue.async { [self] in player?.stop() }
    }

    private func attachedPlayer() -> AVAudioPlayerNode {
        if let player { return player }
        let node = AVAudioPlayerNode()
        graphLock.lock()
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: Self.playbackFormat)
        graphLock.unlock()
        player = node
        return node
    }

    /// Drops the player node so the next `play` attaches a fresh one to the rebuilt graph. A line playing is dropped.
    private func resetPlayback() {
        playbackQueue.sync {
            guard let node = player else { return }
            node.stop()
            graphLock.lock()
            engine.detach(node)
            graphLock.unlock()
            player = nil
        }
    }

    private func convertForPlayback(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target = Self.playbackFormat, buffer.frameLength > 0 else { return nil }
        if buffer.format == target { return buffer }
        let converter = playbackConverters[buffer.format] ?? AVAudioConverter(from: buffer.format, to: target)
        guard let converter else { return nil }
        playbackConverters[buffer.format] = converter
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * target.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        return status == .error || out.frameLength == 0 ? nil : out
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// True while `gen` is still the live capture session (no stop()/restart since it was taken).
    private func isCurrent(_ gen: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return running && generation == gen }

    private func emit(_ e: MicrophoneEvent) {
        let cb = onEvent
        queue.async { cb?(e) }
    }

    private var isEchoUnavailable: Bool { lock.lock(); defer { lock.unlock() }; return echoUnavailable }
    private func markEchoUnavailable() { lock.lock(); echoUnavailable = true; lock.unlock() }

    /// Turns voice processing on (or off, if the config says so) while the engine is stopped, which the
    /// system requires. A refusal marks it unavailable so later rebuilds skip the attempt, and capture goes on plain.
    private func applyVoiceProcessing(_ input: AVAudioInputNode) {
        guard echoCancellation else {
            if input.isVoiceProcessingEnabled { try? input.setVoiceProcessingEnabled(false) }
            return
        }
        guard !isEchoUnavailable, !input.isVoiceProcessingEnabled else { return }
        do {
            try input.setVoiceProcessingEnabled(true)
            // The voice-processing unit needs the output side in the graph to start.
            _ = engine.mainMixerNode
            // The default ducks every other app while voice processing runs; NoHands listens all the time.
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false, duckingLevel: .min)
        } catch {
            markEchoUnavailable()
            try? input.setVoiceProcessingEnabled(false)
        }
    }

    private func installTapAndStart(generation gen: Int) throws {
        graphLock.lock()
        defer { graphLock.unlock() }
        guard isCurrent(gen) else { return }
        let input = engine.inputNode
        applyVoiceProcessing(input)
        do {
            try startEngine(input, generation: gen)
        } catch {
            // Voice processing can make the engine fail to start; retry once on the plain input.
            guard input.isVoiceProcessingEnabled, !isEchoUnavailable else { throw error }
            markEchoUnavailable()
            try? input.setVoiceProcessingEnabled(false)
            try startEngine(input, generation: gen)
        }
        setEchoActive(input.isVoiceProcessingEnabled)
    }

    /// Reads the input format (after voice processing may have changed it), installs the tap and starts the engine.
    private func startEngine(_ input: AVAudioInputNode, generation gen: Int) throws {
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { throw MicrophoneError.noInputFormat }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            // Realtime thread: copy and hand off only.
            guard let self, let copy = Self.copy(buffer) else { return }
            let box = BufferBox(copy)
            self.queue.async { self.consume(box.buffer) }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        // stop() may have run while the engine was starting (it cannot tear down an engine that was not yet
        // running); re-check and tear down so the engine never outlives stop().
        if !isCurrent(gen) {
            input.removeTap(onBus: 0)
            engine.stop()
        }
    }

    /// Runs on `queue` after the engine stopped itself because the hardware configuration changed.
    /// A failed rebuild is retried (see `RestartBackoff`) before `.failed` is emitted.
    private func handleConfigurationChange(generation gen: Int, failures: Int) {
        guard isCurrent(gen) else { return }
        pending.removeAll()
        converter = nil
        let echoWasOn = engine.inputNode.isVoiceProcessingEnabled
        resetPlayback()   // the graph is rebuilt; a line playing is dropped and the next one attaches afresh
        do {
            try installTapAndStart(generation: gen)
            if isCurrent(gen) {
                onEvent?(.restarted)
                // The rebuild fell back to the plain input; say so, since start() reported the earlier state.
                if echoWasOn, echoCancellation, !engine.inputNode.isVoiceProcessingEnabled { onEvent?(.echoCancellation(false)) }
            }
        } catch {
            if let delay = RestartBackoff().delay(afterFailures: failures + 1) {
                queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.handleConfigurationChange(generation: gen, failures: failures + 1)
                }
            } else {
                onEvent?(.failed("microphone restart failed: \(error)"))
            }
        }
    }

    /// Runs on `queue`. Converts to 16 kHz mono and emits exact 4096-sample chunks.
    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: outFormat)
            pending.removeAll()   // partial chunk from a different format is meaningless
        }
        guard let converter else { onEvent?(.failed("no converter for \(buffer.format)")); return }
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let ch = out.floatChannelData, out.frameLength > 0 else { return }
        pending.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
        while pending.count >= Self.chunkSize {
            let chunk = Array(pending.prefix(Self.chunkSize))
            pending.removeFirst(Self.chunkSize)
            onChunk?(chunk)
        }
    }

    /// Copies channel 0 only, as a mono buffer at the source sample rate. A voice-processing input can be
    /// multichannel; channel 0 is the processed voice, and converting every channel would mix in the rest.
    private static func copy(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard !src.format.isInterleaved,
              let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: src.format.sampleRate, channels: 1, interleaved: false),
              let dst = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: src.frameLength),
              let s = src.floatChannelData, let d = dst.floatChannelData else { return nil }
        dst.frameLength = src.frameLength
        // Non-interleaved Float32 (what the input tap delivers): channel 0 is its own plane.
        memcpy(d[0], s[0], Int(src.frameLength) * MemoryLayout<Float>.size)
        return dst
    }
}

private final class BufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(_ b: AVAudioPCMBuffer) { buffer = b }
}
