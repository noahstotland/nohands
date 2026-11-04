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
        Thread.sleep(forTimeInterval: 2)
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
    default:
        usage()
    }
} catch {
    fail("error: \(error)")
}
