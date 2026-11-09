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

@Test func screenshotImageSize() {
    let rows: [(CGSize, CGFloat, CGSize)] = [
        (CGSize(width: 1600, height: 1000), 2, CGSize(width: 1200, height: 750)),   // Retina downscale, aspect kept
        (CGSize(width: 400, height: 300), 1, CGSize(width: 400, height: 300)),      // never upscaled
        (CGSize(width: 400, height: 300), 2, CGSize(width: 800, height: 600)),      // real pixels, under the cap
        (CGSize(width: 0.2, height: 5000), 1, CGSize(width: 1, height: 1200)),      // each side at least 1
    ]
    for (window, scale, expected) in rows {
        #expect(ScreenshotGeometry.imageSize(window: window, backingScale: scale) == expected, "\(window) @\(scale)")
    }
}

private func shot(frame: CGRect, size: CGSize) -> StepScreenshot {
    StepScreenshot(jpeg: Data(), imageSize: size, windowFrame: frame, app: "Safari")
}

@Test func screenshotPointMapping() {
    let rows: [(CGRect, CGSize, CGPoint, CGPoint)] = [
        (CGRect(x: 100, y: 50, width: 1600, height: 1000), CGSize(width: 1200, height: 750), CGPoint(x: 600, y: 375), CGPoint(x: 900, y: 550)),   // Retina
        (CGRect(x: 100, y: 50, width: 800, height: 600), CGSize(width: 800, height: 600), CGPoint(x: 10, y: 20), CGPoint(x: 110, y: 70)),       // 1:1
        (CGRect(x: -1440, y: 0, width: 1000, height: 500), CGSize(width: 500, height: 250), CGPoint(x: 0, y: 0), CGPoint(x: -1440, y: 0)),      // second screen, top-left
        (CGRect(x: -1440, y: 0, width: 1000, height: 500), CGSize(width: 500, height: 250), CGPoint(x: 500, y: 250), CGPoint(x: -440, y: 500)), // bottom-right
    ]
    for (frame, size, image, screen) in rows {
        let s = shot(frame: frame, size: size)
        #expect(ScreenshotGeometry.screenPoint(fromImage: image, shot: s) == screen)
        #expect(ScreenshotGeometry.imagePoint(fromScreen: screen, shot: s) == image)
    }
}

@Test func screenshotMapPoints() {
    let s = shot(frame: CGRect(x: 100, y: 100, width: 800, height: 400), size: CGSize(width: 400, height: 200))
    let click = { (p: CGPoint) in Action.click(.point(p), button: .left, count: 1) }
    let label = Action.click(.label(3), button: .left, count: 1)
    let rows: [([Action], PointMapping)] = [
        ([click(CGPoint(x: 10, y: 20))], .mapped([click(CGPoint(x: 120, y: 140))])),
        ([.moveCursor(.point(CGPoint(x: 400, y: 200)))], .mapped([.moveCursor(.point(CGPoint(x: 900, y: 500)))])),
        ([.drag(from: .point(CGPoint(x: 0, y: 0)), to: .point(CGPoint(x: 100, y: 50))), .wait(ms: 100)],
         .mapped([.drag(from: .point(CGPoint(x: 100, y: 100)), to: .point(CGPoint(x: 300, y: 200))), .wait(ms: 100)])),
        ([click(CGPoint(x: 401, y: 10))], .refused("point outside the screenshot")),
        ([click(CGPoint(x: 10, y: -1))], .refused("point outside the screenshot")),
        ([.wait(ms: 100), click(CGPoint(x: 10, y: 10))], .refused("point must be the step's first action")),
        ([click(CGPoint(x: 10, y: 10)), click(CGPoint(x: 20, y: 20))], .refused("point must be the step's first action")),
        ([label, .scroll(.down, amount: 3)], .mapped([label, .scroll(.down, amount: 3)])),
    ]
    for (actions, expected) in rows { #expect(ScreenshotGeometry.mapPoints(actions, shot: s) == expected, "\(actions)") }
}
