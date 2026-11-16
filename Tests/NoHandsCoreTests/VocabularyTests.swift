import Testing
import Foundation
@testable import NoHandsCore

@Test func vocabularyRewritesWholeHeardSpellings() throws {
    let json = #"[{"hear":"raptures","say":"Raptors"},{"hear":["stream east","streem east"],"say":"StreamEast"},{"hear":"stream","say":"Stream"},{"hear":"bad","say":"bad word"}]"#
    let vocabulary = try JSONDecoder().decode(Vocabulary.self, from: Data(json.utf8))
    let table: [(String, String)] = [
        ("search for raptures", "search for Raptors"),
        ("raptures win", "Raptors win"),
        ("Raptures, again.", "Raptors, again."),
        ("enraptured by raptures", "enraptured by Raptors"),
        ("open stream east now", "open StreamEast now"),
        ("open  STREEM East", "open  StreamEast"),
        ("stream, east", "Stream, east"),
        ("a stream", "a Stream"),
        ("bad bad", "bad word bad word"),
        ("nothing here", "nothing here"),
        ("", ""),
        ("raptures ", "Raptors "),
    ]
    for (heard, expected) in table { #expect(vocabulary.apply(heard) == expected, "\(heard)") }
    #expect(Vocabulary().apply("raptures") == "raptures")
}
