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
        guard rest.count == 1 else { usage() }
        let samples = try loadSamples16k(path: rest[0])
        let asr = try await ParakeetTranscriber(version: "v2")
        for run in 1...4 {
            let t0 = ContinuousClock.now
            let text = try await asr.transcribe(samples)
            let ms = Int(t0.duration(to: .now) / .milliseconds(1))
            print("[run \(run) asr=\(ms)ms audio=\(samples.count * 1000 / 16000)ms] \(text)")
        }
    case "vad-test":
        guard rest.count == 1 else { usage() }
        var samples = try loadSamples16k(path: rest[0])
        samples += [Float](repeating: 0, count: 16_000)   // trailing silence so speechEnd can fire
        let vad = try await VoiceActivity()
        var i = 0
        while i + 4096 <= samples.count {
            let ev = try await vad.process(Array(samples[i..<i + 4096]))
            if ev != .none { print(String(format: "%.2fs %@", Double(i + 4096) / 16000, "\(ev)")) }
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

func listen() async throws {
    let asr = try await ParakeetTranscriber(version: "v2")
    let vad = try await VoiceActivity()
    let mic = try MicrophoneCapture()
    let (stream, cont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
    try mic.start { cont.yield($0) }
    FileHandle.standardError.write(Data("listening... Ctrl-C to quit\n".utf8))
    var assembler = UtteranceAssembler()
    for await chunk in stream {
        let ev = try await vad.process(chunk)
        guard let utterance = assembler.push(chunk, event: ev) else { continue }
        var trace = LatencyTrace()
        trace.speechEnd = .now
        let text = try await asr.transcribe(utterance)
        trace.asrDone = .now
        if !text.isEmpty { print("[\(trace.summary)] \(text)") }
    }
}
