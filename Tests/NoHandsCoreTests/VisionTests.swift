import Testing
import Foundation
@testable import NoHandsCore

// The failure texts here are the ones ActionExecutor produces; TaskRunnerTests pins that they still match.
@Test func visionTriggerRule() {
    let cases: [(String?, [Action], Bool)] = [
        ("no element named 'x'", [], true),
        ("element changed, look again", [.click(.label(1), button: .left, count: 1)], true),
        (nil, [.look], true),
        ("no label 3", [], false),
        (nil, [], false),
        ("point off screen", [], false),
    ]
    for (failure, actions, expected) in cases {
        #expect(VisionTrigger.wantsPicture(lastFailure: failure, lastActions: actions) == expected, "\(failure ?? "nil") \(actions)")
    }
}

@Test func lookDecodesAndSummarizes() throws {
    let step = try IntentDecoder.step(fromPayloadText: #"{"intent":"see","status":"continue","actions":[{"kind":"look"}]}"#)
    #expect(step.actions == [.look])
    #expect(ActionSummary.kinds(step.actions) == "[look]")
}

@Test func visionConfig() throws {
    func cfg(_ json: String) throws -> AppConfig { try AppConfig.load(from: Data(json.utf8), environment: [:]) }
    #expect(try cfg("{}").visionFallback == false)
    #expect(try cfg(#"{"visionFallback":true}"#).visionFallback == true)
    let rows: [(String, Bool)] = [
        (#"{"visionFallback":true,"anthropicAPIKey":"k","intentBackend":"claude"}"#, true),
        (#"{"visionFallback":true,"anthropicAPIKey":"k","intentBackend":"local"}"#, false),
        (#"{"visionFallback":true,"intentBackend":"claude"}"#, false),   // no key: backend is off
        (#"{"anthropicAPIKey":"k","intentBackend":"claude"}"#, false),   // flag off
    ]
    for (json, expected) in rows { #expect(try cfg(json).visionEnabled == expected, "\(json)") }
}
