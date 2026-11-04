import Testing
@testable import NoHandsCore

@Test func mouseStateDragLifecycle() {
    var s = MouseButtonState()
    #expect(s.moveKind == .moved)
    s.down(.left)
    #expect(s.heldButton == .left)
    #expect(s.moveKind == .dragged(.left))
    s.up(.right)
    #expect(s.moveKind == .dragged(.left))
    s.up(.left)
    #expect(s.heldButton == nil)
    #expect(s.moveKind == .moved)
}

@Test func mouseStateUpClearsHeldButton() {
    var s = MouseButtonState()
    s.down(.right)
    s.up(.right)
    #expect(s.heldButton == nil)
    #expect(s.moveKind == .moved)
}
