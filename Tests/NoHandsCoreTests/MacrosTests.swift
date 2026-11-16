import Testing
import Foundation
@testable import NoHandsCore

private func load(_ json: String) throws -> Macros {
    try AppConfig.load(from: Data(#"{"macros":\#(json)}"#.utf8), environment: [:]).macros
}

@Test func macroMatchesTheWholePhraseOnly() throws {
    let macros = try load(#"{"night game":["open chrome","click"]}"#)
    let table: [(String, Bool)] = [
        ("night game", true), ("Night Game.", true), ("night, game!", true),
        ("night game please", false), ("no, night game", false), ("night", false), ("open chrome", false),
    ]
    for (said, hit) in table {
        #expect((macros.match(said)?.steps == ["open chrome", "click"]) == hit, "\(said)")
    }
}

@Test func macroLoadRulesSkipTheWholeMacro() throws {
    let long = String(repeating: "a", count: 201)
    let twentyOne = (0..<21).map { #""click \#($0)""# }.joined(separator: ",")
    let many = (0..<53).map { #""m\#($0)":["click"]"# }.joined(separator: ",")
    // (config value, kept names, skipped)
    let table: [(String, [String], Int)] = [
        (#"{"night game":["open chrome"]}"#, ["night game"], 0),
        (#"{"Night Game!":["Open Chrome "]}"#, ["night game"], 0),
        (#"{"":["click"],"  ":["click"]}"#, [], 2),                                  // empty name
        (#"{"a b c d e f g":["click"]}"#, [], 1),                                    // over 6 words
        (#"{"stop it":["click"],"never mind":["click"],"cancel the game":["click"]}"#, [], 3),
        (#"{"go back":["click"],"click":["click"],"spell":["click"]}"#, [], 3),      // the grammar owns it
        (#"{"a":[]}"#, [], 1),                                                       // no steps
        (#"{"a":["click","","click"],"b":["\#(long)"],"c":[5],"d":"click"}"#, [], 4),
        (#"{"a":[\#(twentyOne)]}"#, [], 1),
        (#"{"a":["click","stop"],"b":["go to sleep"],"c":["wake up"],"d":["start dictating"]}"#, [], 4),
        (#"{"a":["click"],"b":["a"]}"#, ["a"], 1),                                   // a step naming a macro
        (#"{"Night Game":["click"],"night game":["click"],"ok":["click"]}"#, ["ok"], 2),   // same name twice: neither
        (#"{\#(many)}"#, Array((0..<53).map { "m\($0)" }.sorted().prefix(50)), 3),                     // cap, in name order
    ]
    for (json, names, skipped) in table {
        let macros = try load(json)
        #expect(macros.all.map(\.name) == names, "\(json.prefix(60))")
        #expect(macros.skipped == skipped, "\(json.prefix(60))")
    }
}
