import Foundation
import Testing
@testable import NoHandsCore

@Test func speakFeedbackDecodesLeniently() throws {
    let table: [(String?, SpeakLevel)] = [
        (nil, .off), ("{}", .off), (#"{"speakFeedback":"off"}"#, .off), (#"{"speakFeedback":"outcomes"}"#, .outcomes),
        (#"{"speakFeedback":"all"}"#, .all), (#"{"speakFeedback":"loud"}"#, .off), (#"{"speakFeedback":5}"#, .off),
        (#"{"speakFeedback":true}"#, .off), (#"{"speakFeedback":null}"#, .off),
    ]
    for (json, expected) in table {
        #expect(try AppConfig.load(from: json.map { Data($0.utf8) }, environment: [:]).speakFeedback == expected, "\(json ?? "nil")")
    }
}

@Test func speakMenuWritesOnlyItsKey() throws {
    let existing = #"{"anthropicAPIKey": "sk-keep", "gridColumns": 12, "echoCancellation": false, "speakFeedback": "all"}"#
    for level in SpeakLevel.allCases {
        let out = try SpeakMenu.merged(existing: Data(existing.utf8), level: level)
        let object = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect(object["speakFeedback"] as? String == level.rawValue)
        #expect(object.count == 4 && object["gridColumns"] as? Int == 12 && object["echoCancellation"] as? Bool == false)
        #expect(try AppConfig.load(from: out, environment: [:]).speakFeedback == level)
    }
}
