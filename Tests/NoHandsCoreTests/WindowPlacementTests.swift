import Testing
import CoreGraphics
@testable import NoHandsCore

private let visible = CGRect(x: 0, y: 25, width: 1440, height: 875)
private let current = CGRect(x: 100, y: 100, width: 800, height: 600)

@Test func halvesQuartersAndThirds() {
    #expect(WindowPlacement.leftHalf.frame(in: visible, current: current) == CGRect(x: 0, y: 25, width: 720, height: 875))
    #expect(WindowPlacement.rightHalf.frame(in: visible, current: current) == CGRect(x: 720, y: 25, width: 720, height: 875))
    #expect(WindowPlacement.topHalf.frame(in: visible, current: current) == CGRect(x: 0, y: 25, width: 1440, height: 438))
    #expect(WindowPlacement.bottomHalf.frame(in: visible, current: current) == CGRect(x: 0, y: 463, width: 1440, height: 438))
    #expect(WindowPlacement.bottomRight.frame(in: visible, current: current) == CGRect(x: 720, y: 463, width: 720, height: 438))
    #expect(WindowPlacement.middleThird.frame(in: visible, current: current) == CGRect(x: 480, y: 25, width: 480, height: 875))
    #expect(WindowPlacement.rightTwoThirds.frame(in: visible, current: current) == CGRect(x: 480, y: 25, width: 960, height: 875))
    #expect(WindowPlacement.maximize.frame(in: visible, current: current) == visible)
}

@Test func centerKeepsSizeAndClampsToScreen() {
    #expect(WindowPlacement.center.frame(in: visible, current: current) == CGRect(x: 320, y: 163, width: 800, height: 600))
    let huge = CGRect(x: 0, y: 0, width: 5000, height: 5000)
    #expect(WindowPlacement.center.frame(in: visible, current: huge) == visible)
}

@Test func placementsCoverSchemaAndSummary() throws {
    #expect(try IntentDecoder.actions(fromPayloadText: #"{"actions":[{"kind":"move_window","placement":"left_half"}]}"#) == [.moveWindow(.leftHalf)])
    #expect(try IntentDecoder.actions(fromPayloadText: #"{"actions":[{"kind":"move_window","placement":"sideways"},{"kind":"move_window"}]}"#) == [])
    #expect(IntentSchema.kinds.contains("move_window"))
    #expect(IntentSchema.systemPrompt.contains("- move_window:"))
    for p in WindowPlacement.allCases { #expect(IntentSchema.systemPrompt.contains(p.rawValue)) }
    #expect(ActionSummary.kind(.moveWindow(.maximize)) == "moveWindow(maximize)")
}
