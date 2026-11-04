import Foundation
import Testing
@testable import NoHandsCore

@Test func keyCodesMatchCarbon() {
    #expect(Key.a.keyCode == 0)
    #expect(Key.return.keyCode == 36)
    #expect(Key.space.keyCode == 49)
    #expect(Key.delete.keyCode == 51)
    #expect(Key.escape.keyCode == 53)
    #expect(Key.left.keyCode == 123)
    #expect(Key.up.keyCode == 126)
}

@Test func spokenKeyNames() {
    #expect(Key.named("enter") == .return)
    #expect(Key.named("backspace") == .delete)
    #expect(Key.named("escape") == .escape)
    #expect(Key.named("f5") == .f5)
    #expect(Key.named("seven") == .seven)
    #expect(Key.named("banana") == nil)
}

@Test func actionRoundTripsThroughJSON() throws {
    let actions: [Action] = [.click(.numbered(42), button: .left, count: 2), .pressKey(KeyChord(.s, [.command])), .moveCursor(.relative(dx: -50, dy: 0))]
    let data = try JSONEncoder().encode(actions)
    #expect(try JSONDecoder().decode([Action].self, from: data) == actions)
}
