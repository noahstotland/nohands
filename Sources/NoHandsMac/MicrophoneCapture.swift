import AVFoundation
import Foundation

public enum MicrophoneError: Error { case noInputFormat, converterUnavailable }

/// Captures the default input device as 16 kHz mono Float32 in exact 4096-sample chunks.
///
/// Threading: the AVAudioEngine tap runs on a realtime audio thread. In the tap we only convert
/// the buffer and append to a lock-protected accumulator; completed chunks are copied out and
/// delivered to `onChunk` on a private serial queue, never on the audio thread.
public final class MicrophoneCapture: @unchecked Sendable {
    public static let chunkSize = 4096

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "nohands.mic.chunks", qos: .userInteractive)
    private let lock = NSLock()
    private var pending: [Float] = []   // guarded by lock
    private var running = false         // guarded by lock

    public init() throws {}

    /// 16 kHz mono Float32 chunks of exactly 4096 samples (VadManager.chunkSize), delivered on a background queue.
    public func start(_ onChunk: @escaping @Sendable ([Float]) -> Void) throws {
        lock.lock()
        if running { lock.unlock(); return }
        running = true
        pending.removeAll()
        lock.unlock()

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, inFormat.channelCount > 0 else { running = false; throw MicrophoneError.noInputFormat }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat)
        else { running = false; throw MicrophoneError.converterUnavailable }

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let box = ConverterBox(converter)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            // Realtime thread: convert, then hand off.
            guard let self else { return }
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            let status = box.converter.convert(to: out, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, let ch = out.floatChannelData, out.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
            var chunks: [[Float]] = []
            self.lock.lock()
            self.pending.append(contentsOf: samples)
            while self.pending.count >= Self.chunkSize {
                chunks.append(Array(self.pending.prefix(Self.chunkSize)))
                self.pending.removeFirst(Self.chunkSize)
            }
            self.lock.unlock()
            for c in chunks { self.queue.async { onChunk(c) } }
        }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            lock.lock(); running = false; lock.unlock()
            throw error
        }
    }

    public func stop() {
        lock.lock()
        let was = running
        running = false
        pending.removeAll()
        lock.unlock()
        guard was else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

private final class ConverterBox: @unchecked Sendable {
    let converter: AVAudioConverter
    init(_ c: AVAudioConverter) { converter = c }
}
