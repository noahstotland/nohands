import Testing
import CoreGraphics
@testable import NoHandsCore

private let grid = GridModel(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800))
private let save = UIElementInfo(id: 1, frame: CGRect(x: 100, y: 100, width: 80, height: 30), title: "Save", role: "AXButton")

@Test func numberedResolvesAgainstVisibleOverlay() {
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .grid(grid), cursor: .zero, elements: []) == .point(CGPoint(x: 50, y: 50)))
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .labels([1: save]), cursor: .zero, elements: []) == .point(CGPoint(x: 140, y: 115)))
}

@Test func numberedTargetOutOfRangeIsReported() {
    #expect(TargetResolver.resolveClick(.numbered(150), overlay: .grid(grid), cursor: .zero, elements: []) == .failure("no cell 150"))
    #expect(TargetResolver.resolveClick(.numbered(7), overlay: .none, cursor: .zero, elements: []) == .failure("no grid or labels shown"))
    #expect(TargetResolver.resolveClick(.numbered(2), overlay: .labels([1: save]), cursor: .zero, elements: []) == .failure("no label 2"))
}

@Test func elementAndCursorTargets() {
    #expect(TargetResolver.resolveClick(.element(named: "save"), overlay: .none, cursor: .zero, elements: [save]) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveClick(.element(named: "quit"), overlay: .none, cursor: .zero, elements: [save]) == .failure("no element named 'quit'"))
    #expect(TargetResolver.resolveClick(.cursor, overlay: .none, cursor: CGPoint(x: 5, y: 6), elements: []) == .point(CGPoint(x: 5, y: 6)))
    #expect(TargetResolver.resolveMove(.relative(dx: -10, dy: 20), overlay: .none, cursor: CGPoint(x: 100, y: 100), elements: []) == .point(CGPoint(x: 90, y: 120)))
}

@Test func pointAndMoveTargets() {
    let p = CGPoint(x: 7, y: 8)
    #expect(TargetResolver.resolveClick(.point(p), overlay: .none, cursor: .zero, elements: []) == .point(p))
    #expect(TargetResolver.resolveMove(.point(p), overlay: .none, cursor: .zero, elements: []) == .point(p))
    #expect(TargetResolver.resolveMove(.numbered(1), overlay: .grid(grid), cursor: .zero, elements: []) == .point(CGPoint(x: 50, y: 50)))
    #expect(TargetResolver.resolveMove(.element(named: "save"), overlay: .none, cursor: .zero, elements: [save]) == .point(CGPoint(x: 140, y: 115)))
    #expect(TargetResolver.resolveMove(.numbered(3), overlay: .none, cursor: .zero, elements: []) == .failure("no grid or labels shown"))
}

@Test func partlyOffScreenLabelClicksVisiblePart() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let edge = UIElementInfo(id: 2, frame: CGRect(x: 950, y: 100, width: 100, height: 40), title: "Edge", role: "AXButton")
    // visible part is x 950...1000 -> center 975
    #expect(TargetResolver.resolveClick(.numbered(1), overlay: .labels([1: edge]), cursor: .zero, elements: [], screens: [screen]) == .point(CGPoint(x: 975, y: 120)))
    #expect(TargetResolver.resolveClick(.element(named: "edge"), overlay: .none, cursor: .zero, elements: [edge], screens: [screen]) == .point(CGPoint(x: 975, y: 120)))
}
