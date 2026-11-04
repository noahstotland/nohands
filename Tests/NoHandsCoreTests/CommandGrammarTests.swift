import Testing
import Foundation
@testable import NoHandsCore

let g = CommandGrammar()

@Test func normalizesAsrPunctuation() {
    #expect(CommandGrammar.normalize("  Click 42. ") == ["click", "42"])
    #expect(g.parse("Press Enter.") == [.pressKey(KeyChord(.return))])
}

@Test func modeCommands() {
    #expect(g.parse("start dictating") == [.setMode(.dictation)])
    #expect(g.parse("dictation mode") == [.setMode(.dictation)])
    #expect(g.parse("stop dictating") == [.setMode(.command)])
    #expect(g.parse("command mode") == [.setMode(.command)])
    #expect(g.parse("go to sleep") == [.setMode(.sleep)])
    #expect(g.parse("wake up") == [.setMode(.command)])
}

@Test func keysAndShortcuts() {
    #expect(g.parse("press command shift s") == [.pressKey(KeyChord(.s, [.command, .shift]))])
    #expect(g.parse("press escape") == [.pressKey(KeyChord(.escape))])
    #expect(g.parse("enter") == [.pressKey(KeyChord(.return))])
    #expect(g.parse("backspace") == [.pressKey(KeyChord(.delete))])
    #expect(g.parse("left") == [.pressKey(KeyChord(.left))])
    #expect(g.parse("undo") == [.pressKey(KeyChord(.z, [.command]))])
    #expect(g.parse("redo") == [.pressKey(KeyChord(.z, [.command, .shift]))])
    #expect(g.parse("select all") == [.pressKey(KeyChord(.a, [.command]))])
    #expect(g.parse("switch app") == [.pressKey(KeyChord(.tab, [.command]))])
    #expect(g.parse("spotlight") == [.pressKey(KeyChord(.space, [.command]))])
    #expect(g.parse("delete word") == [.pressKey(KeyChord(.delete, [.option]))])
    #expect(g.parse("delete line") == [.pressKey(KeyChord(.delete, [.command]))])
}

@Test func mouseCommands() {
    #expect(g.parse("click") == [.click(.cursor, button: .left, count: 1)])
    #expect(g.parse("double click") == [.click(.cursor, button: .left, count: 2)])
    #expect(g.parse("right click") == [.click(.cursor, button: .right, count: 1)])
    #expect(g.parse("click forty two") == [.click(.numbered(42), button: .left, count: 1)])
    #expect(g.parse("click to") == [.click(.numbered(2), button: .left, count: 1)])
    #expect(g.parse("click save") == [.click(.element(named: "save"), button: .left, count: 1)])
    #expect(g.parse("click the save button") == [.click(.element(named: "save button"), button: .left, count: 1)])
    #expect(g.parse("hold click") == [.pressMouse(.left)])
    #expect(g.parse("release click") == [.releaseMouse(.left)])
    #expect(g.parse("move up") == [.moveCursor(.relative(dx: 0, dy: -50))])
    #expect(g.parse("move right 120") == [.moveCursor(.relative(dx: 120, dy: 0))])
    #expect(g.parse("move to 12") == [.moveCursor(.numbered(12))])
    #expect(g.parse("scroll down") == [.scroll(.down, amount: 5)])
    #expect(g.parse("scroll up 500") == [.scroll(.up, amount: 50)])
}

@Test func overlaysAndApps() {
    #expect(g.parse("grid") == [.showGrid])
    #expect(g.parse("show grid") == [.showGrid])
    #expect(g.parse("zoom 35") == [.zoomGrid(35)])
    #expect(g.parse("show numbers") == [.showLabels])
    #expect(g.parse("numbers") == [.showLabels])
    #expect(g.parse("hide") == [.hideOverlay])
    #expect(g.parse("cancel") == [.hideOverlay])
    #expect(g.parse("open safari") == [.openApp("safari")])
    #expect(g.parse("open visual studio code") == [.openApp("visual studio code")])
}

@Test func typeCommandAndUnmatched() {
    #expect(g.parse("type hello world") == [.typeText("hello world")])
    #expect(g.parse("make this window full screen") == nil)
    #expect(g.parse("") == nil)
}

@Test func hyphenatedAndStrictRemainders() {
    #expect(g.parse("click forty-two") == [.click(.numbered(42), button: .left, count: 1)])
    #expect(g.parse("move right 10 pixels") == nil)
    #expect(g.parse("scroll down 3 more") == nil)
    #expect(g.parse("press") == nil)
    #expect(g.parse("press foo enter") == nil)
}

@Test func editingShortcutsAndDeletes() {
    #expect(g.parse("copy") == [.pressKey(KeyChord(.c, [.command]))])
    #expect(g.parse("paste") == [.pressKey(KeyChord(.v, [.command]))])
    #expect(g.parse("cut") == [.pressKey(KeyChord(.x, [.command]))])
    #expect(g.parse("save") == [.pressKey(KeyChord(.s, [.command]))])
    #expect(g.parse("find") == [.pressKey(KeyChord(.f, [.command]))])
    #expect(g.parse("new tab") == [.pressKey(KeyChord(.t, [.command]))])
    #expect(g.parse("close tab") == [.pressKey(KeyChord(.w, [.command]))])
    #expect(g.parse("close window") == [.pressKey(KeyChord(.w, [.command, .shift]))])
    #expect(g.parse("quit app") == [.pressKey(KeyChord(.q, [.command]))])
    #expect(g.parse("delete") == [.pressKey(KeyChord(.delete))])
    #expect(g.parse("forward delete") == [.pressKey(KeyChord(.forwardDelete))])
}

@Test func overlayAliases() {
    #expect(g.parse("show labels") == [.showLabels])
    #expect(g.parse("hide grid") == [.hideOverlay])
    #expect(g.parse("hide numbers") == [.hideOverlay])
}

@Test func extraClicksPressAliasesAndScroll() {
    #expect(g.parse("triple click") == [.click(.cursor, button: .left, count: 3)])
    #expect(g.parse("middle click") == [.click(.cursor, button: .middle, count: 1)])
    #expect(g.parse("press cmd alt ctrl t") == [.pressKey(KeyChord(.t, [.command, .option, .control]))])
    #expect(g.parse("press command shift") == nil)
    #expect(g.parse("scroll left") == [.scroll(.left, amount: 5)])
    #expect(g.parse("scroll right 7") == [.scroll(.right, amount: 7)])
}
