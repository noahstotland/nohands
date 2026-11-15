import Foundation
import Testing
@testable import NoHandsCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let gb = Locale(identifier: "en_GB")
private let utc = TimeZone(identifier: "UTC")!
private func clock(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .standard, locale: gb, timeZone: utc))
}
private let time0 = clock(t0)
private let time3 = clock(t0.addingTimeInterval(3))

private func entry(_ n: Int = 0, outcome: CommandLogEntry.Outcome = .done, resolver: CommandLogEntry.Resolver = .grammar,
                   steps: [CommandLogEntry.Step] = [], usage: CommandLogEntry.Usage? = nil) -> CommandLogEntry {
    CommandLogEntry(date: t0.addingTimeInterval(Double(n)), phrase: "phrase \(n)", resolver: resolver, steps: steps,
                    outcome: outcome, durationMs: 1500, usage: usage)
}

@Test func commandLogKeepsNewest50() {
    for (count, expected) in [(1, 1), (50, 50), (51, 50), (60, 50)] {
        var log = CommandLog()
        for n in 0..<count { log.append(entry(n)) }
        #expect(log.entries.count == expected, "\(count) appended")
        #expect(log.entries.first?.phrase == "phrase \(count - 1)", "newest first, \(count) appended")
        #expect(log.entries.last?.phrase == "phrase \(count - expected)", "oldest kept, \(count) appended")
    }
}

@Test func commandLogDecodeNeverFails() throws {
    struct Raw: Codable { let entries: [CommandLogEntry] }
    func file(_ entries: [CommandLogEntry]) throws -> Data {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        return try e.encode(Raw(entries: entries))
    }
    let three = (0..<3).map { entry($0, steps: [.init(number: 1, action: "a", result: .failed("x"))]) }
    let oneBad = String(decoding: try file(three), as: UTF8.self)
        .replacingOccurrences(of: "\"phrase\"", with: "\"nope\"")   // every entry loses a required key
    let cases: [(String, Data?, Int)] = [
        ("missing", nil, 0), ("empty", Data(), 0), ("invalid JSON", Data("{nope".utf8), 0),
        ("wrong shape", Data("[1,2]".utf8), 0), ("bad entry", Data(oneBad.utf8), 0),
        ("60 valid, trimmed", try file((0..<60).map { entry($0) }), 50),
    ]
    for (name, data, count) in cases { #expect(CommandLog.decode(data).entries.count == count, Comment(rawValue: name)) }
    #expect(CommandLog.decode(try CommandLog(entries: three).encoded()).entries == three, "round trip")
}

@Test func taskTrailTimesSteps() {
    var t = TaskTrail(maxSteps: 5)
    t.begin(number: 1, intent: "a", at: t0)
    t.begin(number: 2, intent: "b", at: t0)
    t.end(number: 1, failure: nil, at: t0.addingTimeInterval(1.5))
    t.end(number: 2, failure: "no field", at: t0.addingTimeInterval(2))
    #expect(t.steps[0].startedAt == t0 && t.steps[0].duration == .seconds(1.5) && t.steps[0].state == .done)
    #expect(t.steps[1].state == .failed("no field") && t.steps[1].duration == .seconds(2))
    let before = t
    t.end(number: 1, failure: "late", at: t0.addingTimeInterval(9))   // already ended
    t.end(number: 7, failure: nil, at: t0.addingTimeInterval(9))      // unknown
    #expect(t == before)
}

@Test func entryFromTrail() {
    var t = TaskTrail(maxSteps: 5)
    t.begin(number: 1, intent: "open", at: t0)
    t.end(number: 1, failure: nil, at: t0.addingTimeInterval(1))
    t.begin(number: 2, intent: "click", at: t0.addingTimeInterval(1))
    t.end(number: 2, failure: "no element", at: t0.addingTimeInterval(2))
    t.begin(number: 3, intent: "type", at: t0.addingTimeInterval(2))
    let cases: [(CommandLogEntry.Outcome, CommandLogEntry.Outcome)] = [
        (.done, .done), (.stopped, .stopped), (.failed("stuck"), .failed("stuck")),
    ]
    for (ending, lastStep) in cases {
        let e = CommandLogEntry.fromTrail(t, date: t0, phrase: "p", resolver: .claude, outcome: ending, durationMs: 3000, usage: nil)
        #expect(e.steps.map(\.number) == [1, 2, 3])
        #expect(e.steps[1].result == .failed("no element") && e.steps[0].durationMs == 1000)
        #expect(e.steps[2].result == lastStep, "running step takes the ending \(ending)")
        #expect(e.steps[2].durationMs == 1000, "running step runs to the task's end (t0 + 3 s)")
    }
    let a = ClaudeUsage(inputTokens: 10, cacheReadTokens: 100, cacheWriteTokens: 1)
    let b = ClaudeUsage(inputTokens: 5, cacheReadTokens: 50, cacheWriteTokens: 2)
    #expect(CommandLogEntry.Usage.sum([]) == nil)
    #expect(CommandLogEntry.Usage.sum([a, b]) == .init(calls: 2, inputTokens: 15, cacheReadTokens: 150, cacheWriteTokens: 3))
}

@Test func commandLogTextRendersEveryPart() {
    let steps: [CommandLogEntry.Step] = [
        .init(number: 1, action: "Open youtube.com", result: .done, startedAt: t0, durationMs: 1200),
        .init(number: 2, action: "Click the first video", result: .failed("no element"), startedAt: t0.addingTimeInterval(3), durationMs: 400),
    ]
    let usage = CommandLogEntry.Usage(calls: 4, inputTokens: 12_340, cacheReadTokens: 48_100, cacheWriteTokens: 3_200)
    let claude = entry(0, outcome: .failed("stuck"), resolver: .claude, steps: steps, usage: usage)
    let text = CommandLogText.detail(claude, locale: gb, timeZone: utc).split(separator: "\n").map(String.init)
    #expect(text == [
        "\(time0) \u{00B7} \u{201C}phrase 0\u{201D} \u{00B7} Claude",
        "1. Open youtube.com \u{00B7} done \u{00B7} \(time0) \u{00B7} 1.2 s",
        "2. Click the first video \u{00B7} failed: no element \u{00B7} \(time3) \u{00B7} 0.4 s",
        "Failed: stuck \u{00B7} 1.5 s",
        "Claude: 4 calls \u{00B7} 12,340 in \u{00B7} 48,100 cache read \u{00B7} 3,200 cache write",
    ])
    let grammar = CommandLogText.detail(entry(1), locale: gb, timeZone: utc)
    #expect(grammar.contains("Grammar") && grammar.hasSuffix("Done \u{00B7} 1.5 s") && !grammar.contains("Claude:"))
    #expect(CommandLogText.menuLine(claude) == "phrase 0 \u{00B7} failed")
    let long = entry(0, outcome: .ignored("hint"), resolver: .none)
    #expect(CommandLogText.menuLine(CommandLogEntry(date: t0, phrase: String(repeating: "word ", count: 30), resolver: .none,
                                                    steps: [], outcome: .ignored("hint"), durationMs: 0)).count <= 60)
    #expect(CommandLogText.detail(long, locale: gb, timeZone: utc).contains("Ignored: hint"))
}

