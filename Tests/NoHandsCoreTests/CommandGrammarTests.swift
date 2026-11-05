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
    // Compound requests fall through to the LLM instead of being read as an app name.
    // Known websites open in the default browser (or the named one) without a round trip to the model.
    let yt = URL(string: "https://www.youtube.com")!
    #expect(g.parse("open youtube") == [.openURL(yt, app: nil)])
    #expect(g.parse("Open YouTube.") == [.openURL(yt, app: nil)])
    #expect(g.parse("open youtube on chrome") == [.openURL(yt, app: "chrome")])
    #expect(g.parse("open youtube in google chrome") == [.openURL(yt, app: "google chrome")])
    #expect(g.parse("open youtube.com") == [.openURL(URL(string: "https://youtube.com")!, app: nil)])
    #expect(g.parse("open youtube and search for cats") == nil)
    #expect(g.parse("open documents") == [.openApp("documents")])
    #expect(g.parse("open documents in finder") == nil)
    #expect(g.parse("open google chrome and go to youtube") == nil)
}

@Test func typeCommandAndUnmatched() {
    #expect(g.parse("type hello world") == [.typeText("Hello world")])
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

@Test func typePayloadKeepsRawCasing() {
    #expect(g.parse("type send it to NASA") == [.typeText("Send it to NASA")])
    #expect(g.parse("Type Hello, I'm Noah.") == [.typeText("Hello, I'm Noah.")])
    #expect(g.parse("type hello comma world") == [.typeText("Hello, world")])
    #expect(g.parse("type") == nil)
}

@Test func accessibilityShortcuts() {
    #expect(g.parse("minimize") == [.pressKey(KeyChord(.m, [.command]))])
    #expect(g.parse("minimize window") == [.pressKey(KeyChord(.m, [.command]))])
    #expect(g.parse("full screen") == [.pressKey(KeyChord(.f, [.command, .control]))])
    #expect(g.parse("hide app") == [.pressKey(KeyChord(.h, [.command]))])
    #expect(g.parse("reload") == [.pressKey(KeyChord(.r, [.command]))])
    #expect(g.parse("refresh") == [.pressKey(KeyChord(.r, [.command]))])
    #expect(g.parse("go back") == [.pressKey(KeyChord(.leftBracket, [.command]))])
    #expect(g.parse("go forward") == [.pressKey(KeyChord(.rightBracket, [.command]))])
    #expect(g.parse("next tab") == [.pressKey(KeyChord(.tab, [.control]))])
    #expect(g.parse("previous tab") == [.pressKey(KeyChord(.tab, [.control, .shift]))])
    // A site name or domain opens in the default browser; anything else still goes through the address bar.
    #expect(g.parse("go to youtube") == [.openURL(URL(string: "https://www.youtube.com")!, app: nil)])
    #expect(g.parse("go to example.org/docs") == [.openURL(URL(string: "https://example.org/docs")!, app: nil)])
    let nav: [Action] = [.pressKey(KeyChord(.l, [.command])), .typeText("my dashboard"), .pressKey(KeyChord(.return))]
    #expect(g.parse("go to my dashboard") == nav)
    #expect(g.parse("Search for cute cats.") == [.pressKey(KeyChord(.l, [.command])), .typeText("cute cats"),
                                                .pressKey(KeyChord(.return))])
    #expect(g.parse("go to sleep") == [.setMode(.sleep)])   // exact phrase still wins
    #expect(g.parse("go to") == nil)
    #expect(g.parse("search for") == nil)
}

@Test func fillerWordsStrippedForExactCommands() {
    let closeTab: [Action] = [.pressKey(KeyChord(.w, [.command]))]
    #expect(g.parse("close the current tab") == closeTab)
    #expect(g.parse("close this tab") == closeTab)
    #expect(g.parse("Close the tab.") == closeTab)
    #expect(g.parse("close current tab") == closeTab)
    #expect(g.parse("close the window") == [.pressKey(KeyChord(.w, [.command, .shift]))])
    #expect(g.parse("close this window") == [.pressKey(KeyChord(.w, [.command, .shift]))])
    #expect(g.parse("hide the grid") == [.hideOverlay])
    #expect(g.parse("go to sleep") == [.setMode(.sleep)])
    // Only exact entries benefit: pattern rules keep their original tokens.
    #expect(g.parse("click the save") == [.click(.element(named: "save"), button: .left, count: 1)])
    #expect(g.parse("type the word") == [.typeText("The word")])
    #expect(g.parse("close the current tab and open a new one") == nil)
    #expect(g.parse("the") == nil)
    // Pattern rules win over filler stripping: "to" is the homophone of two here, and "open the" is an app name.
    #expect(g.parse("click to") == [.click(.numbered(2), button: .left, count: 1)])
    #expect(g.parse("press the enter") == nil)
    #expect(g.parse("scroll to the down") == nil)
}

@Test func windowPlacementCommands() {
    #expect(g.parse("left half") == [.moveWindow(.leftHalf)])
    #expect(g.parse("right half") == [.moveWindow(.rightHalf)])
    #expect(g.parse("snap left") == [.moveWindow(.leftHalf)])
    #expect(g.parse("snap to the left") == [.moveWindow(.leftHalf)])
    #expect(g.parse("snap to the right side") == [.moveWindow(.rightHalf)])
    #expect(g.parse("top left") == [.moveWindow(.topLeft)])
    #expect(g.parse("bottom right") == [.moveWindow(.bottomRight)])
    #expect(g.parse("maximize") == [.moveWindow(.maximize)])
    #expect(g.parse("maximize the window") == [.moveWindow(.maximize)])
    #expect(g.parse("fill the screen") == [.moveWindow(.maximize)])
    #expect(g.parse("center the window") == [.moveWindow(.center)])
    // Rich phrasing is the model's job.
    #expect(g.parse("make the window half width and snap to the left side of the screen") == nil)
    #expect(g.parse("left") == [.pressKey(KeyChord(.left))])
}
