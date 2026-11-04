import Foundation
import CoreGraphics
import NoHandsCore
import NoHandsMac

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    fail("""
    usage:
      nohands-cli type "<text>"      (waits 2 s, then types)
      nohands-cli key "<chord>"      e.g. "command shift s"
      nohands-cli click-at <x> <y>
      nohands-cli move <x> <y>
      nohands-cli transcribe <wav>
      nohands-cli vad-test <wav>
      nohands-cli listen             (mic -> VAD -> ASR; Ctrl-C to quit)
    """)
}

func point(_ args: [String]) -> CGPoint {
    guard args.count == 2, let x = Double(args[0]), let y = Double(args[1]), x.isFinite, y.isFinite else { usage() }
    return CGPoint(x: x, y: y)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
let rest = Array(args.dropFirst())
let synth = CGEventInputSynthesizer()

do {
    switch command {
    case "type":
        guard rest.count == 1 else { usage() }
        try await Task.sleep(for: .seconds(2))
        try synth.type(rest[0])
    case "key":
        guard rest.count == 1 else { usage() }
        guard let actions = CommandGrammar().parse("press " + rest[0]) else {
            fail("could not parse key spec: \(rest[0])")
        }
        guard actions.count == 1, case .pressKey(let chord) = actions[0] else {
            fail("key spec did not parse as a key press: \(rest[0])")
        }
        try synth.press(chord)
    case "click-at":
        try synth.click(at: point(rest), button: .left, count: 1)
    case "move":
        try synth.moveMouse(to: point(rest))
    case "transcribe":
        // transcribe <wav> [version] [encoderUnits] [precision]
        guard rest.count >= 1, rest.count <= 4 else { usage() }
        let samples = try loadSamples16k(path: rest[0])
        let t0 = ContinuousClock.now
        let asr = try await ParakeetTranscriber(
            version: rest.count > 1 ? rest[1] : "v2",
            encoderUnits: rest.count > 2 ? (rest[2] == "default" ? nil : rest[2]) : "gpu",
            precision: rest.count > 3 ? rest[3] : nil)
        print("load=\(Int(t0.duration(to: .now) / .milliseconds(1)))ms")
        var times: [Int] = []
        var text = ""
        for _ in 1...(Int(ProcessInfo.processInfo.environment["NH_RUNS"] ?? "") ?? 8) {
            let t = ContinuousClock.now
            text = try await asr.transcribe(samples)
            times.append(Int(t.duration(to: .now) / .milliseconds(1)))
        }
        print("last breakdown: \(await asr.lastBreakdown)")
        let warm = times.dropFirst(2).sorted()
        print("runs=\(times) warm-median=\(warm[warm.count / 2])ms audio=\(samples.count * 1000 / 16000)ms text=\(text)")
    case "vad-test":
        // vad-test <wav> [silenceMs] [speechThreshold] [negativeThreshold]
        guard rest.count >= 1, rest.count <= 4 else { usage() }
        var samples = try loadSamples16k(path: rest[0])
        // True end of the last speech: last 20 ms window with RMS above 0.005.
        var trueEnd = 0
        var w = 0
        while w + 320 <= samples.count {
            var e: Float = 0
            for v in samples[w..<w + 320] { e += v * v }
            if (e / 320).squareRoot() > 0.005 { trueEnd = w + 320 }
            w += 320
        }
        samples += [Float](repeating: 0, count: 24_000)   // trailing silence so speechEnd can fire
        let vad = try await VoiceActivity(
            silenceMs: rest.count > 1 ? Int(rest[1]) ?? 350 : 350,
            speechThreshold: rest.count > 2 ? Float(rest[2]) ?? 0.85 : 0.85,
            negativeThreshold: rest.count > 3 ? Float(rest[3]) : nil)
        var i = 0
        while i + 4096 <= samples.count {
            let ev = try await vad.process(Array(samples[i..<i + 4096]))
            if ev != .none {
                let t = Double(i + 4096) / 16000
                var line = String(format: "%.2fs %@", t, "\(ev)")
                if ev == .speechEnd { line += String(format: "  lag=%.0fms (true speech end %.2fs)", (t - Double(trueEnd) / 16000) * 1000, Double(trueEnd) / 16000) }
                print(line)
            }
            i += 4096
        }
    case "listen":
        try await listen()
    default:
        usage()
    }
} catch {
    fail("error: \(error)")
}

enum Log {
    static func err(_ m: String) { FileHandle.standardError.write(Data((m + "\n").utf8)) }
}

/// mic -> VAD -> assembler -> (bounded queue, newest 2) -> ASR. The VAD loop never waits on ASR.
func listen() async throws {
    let asr = try await ParakeetTranscriber(version: "v2")
    let vad = try await VoiceActivity()
    let mic = try MicrophoneCapture()
    mic.onEvent = { Log.err("[mic] \($0)") }
    let (chunks, chunkCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
    // Keep at most 2 pending utterances; when full the OLDEST is dropped (reported via the yield result).
    let (utterances, uttCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingNewest(2))
    try mic.start { chunkCont.yield($0) }
    Log.err("listening... Ctrl-C to quit")
    defer { mic.stop(); chunkCont.finish(); uttCont.finish() }

    let asrTask = Task {
        for await utterance in utterances {
            var trace = LatencyTrace()
            trace.speechEnd = .now
            do {
                let text = try await asr.transcribe(utterance)
                trace.asrDone = .now
                if !text.isEmpty { print("[\(trace.summary)] \(text)") }
            } catch {
                Log.err("asr error (utterance skipped): \(error)")
            }
        }
    }
    defer { asrTask.cancel() }

    var assembler = UtteranceAssembler()
    for await chunk in chunks {
        do {
            let ev = try await vad.process(chunk)
            if let utterance = assembler.push(chunk, event: ev) {
                if case .dropped = uttCont.yield(utterance) { Log.err("asr backlog: dropped oldest pending utterance") }
            }
        } catch {
            Log.err("vad error (state reset): \(error)")
            await vad.reset()
            assembler.reset()
        }
    }
}
