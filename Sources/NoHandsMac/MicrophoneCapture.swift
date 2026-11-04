import AVFoundation
import Foundation
import NoHandsCore

public enum MicrophoneError: Error { case noInputFormat, converterUnavailable }

public enum MicrophoneEvent: Sendable, Equatable {
    case started
    /// The audio configuration changed (device switch, sample-rate change) and capture was rebuilt.
    case restarted
    case failed(String)
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
    private var _onEvent: (@Sendable (MicrophoneEvent) -> Void)?
    private var running = false                              // guarded by lock
    private var generation = 0                               // guarded by lock; bumped by every start/stop
    private var observer: NSObjectProtocol?                  // guarded by lock
    // Queue-confined:
    private var onChunk: (@Sendable ([Float]) -> Void)?
    private var converter: AVAudioConverter?
    private var pending: [Float] = []

    public init() throws {
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
        let token = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in self?.handleConfigurationChange(generation: gen, failures: 0) }
        }
        lock.lock(); observer = token; lock.unlock()
        emit(.started)
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
        queue.sync { self.onChunk = nil; self.pending.removeAll(); self.converter = nil }
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    /// True while `gen` is still the live capture session (no stop()/restart since it was taken).
    private func isCurrent(_ gen: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return running && generation == gen }

    private func emit(_ e: MicrophoneEvent) {
        let cb = onEvent
        queue.async { cb?(e) }
    }

    private func installTapAndStart(generation gen: Int) throws {
        guard isCurrent(gen) else { return }
        let input = engine.inputNode
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
        do {
            try installTapAndStart(generation: gen)
            if isCurrent(gen) { onEvent?(.restarted) }
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

    private static func copy(_ src: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let dst = AVAudioPCMBuffer(pcmFormat: src.format, frameCapacity: src.frameLength),
              let s = src.floatChannelData, let d = dst.floatChannelData else { return nil }
        dst.frameLength = src.frameLength
        for c in 0..<Int(src.format.channelCount) {
            memcpy(d[c], s[c], Int(src.frameLength) * MemoryLayout<Float>.size)
        }
        return dst
    }
}

private final class BufferBox: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    init(_ b: AVAudioPCMBuffer) { buffer = b }
}
