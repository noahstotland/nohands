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
    #expect(g.parse("go to sleep") == [.setMode(.sleep)])   // exact phrase still wins
    #expect(g.parse("go to") == nil)
    #expect(g.parse("search for") == nil)
}

@Test func searchForUsesTheFrontAppOrTheNamedSite() {
    // The frontmost app's or page's own search box (the executor picks the box, the results page, or the address bar).
    #expect(g.parse("Search for cute cats.") == [.search("cute cats")])
    #expect(g.parse("search for Outdoor Boys") == [.search("Outdoor Boys")])
    #expect(g.parse("search for cats in the kitchen") == [.search("cats in the kitchen")])   // not a site
    // A named site: searched in place when it is open, else its results page (the executor decides).
    let yt: [Action] = [.searchSite("outdoor boys", site: "youtube.com")]
    #expect(g.parse("search for outdoor boys on youtube") == yt)
    #expect(g.parse("search for outdoor boys on YouTube.") == yt)
    #expect(g.parse("search for outdoor boys in youtube") == yt)
    #expect(g.parse("search youtube for outdoor boys") == yt)
    #expect(g.parse("search google maps for coffee") == [.searchSite("coffee", site: "maps.google.com")])
    #expect(g.parse("search youtube for") == nil)
    #expect(g.parse("search for on youtube") == [.search("on youtube")])   // no words before "on"
    #expect(g.parse("search the web for cats") == nil)   // not a known site: the model decides
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

@Test func findOnPageAndScrollToWords() {
    let table: [(String, [Action]?)] = [
        ("find the Raptors game", [.findOnPage("the Raptors game", movePointer: true)]),
        ("Find Outdoor Boys.", [.findOnPage("Outdoor Boys", movePointer: true)]),
        ("scroll to the schedule", [.findOnPage("the schedule", movePointer: true)]),
        ("scroll to top gear", [.findOnPage("top gear", movePointer: true)]),
        ("find", [.pressKey(KeyChord(.f, [.command]))]),               // bare find stays command-F
        ("find the", [.pressKey(KeyChord(.f, [.command]))]),
        ("scroll to", nil), ("scroll to the down", nil), ("scroll to the left", nil),
        ("scroll down", [.scroll(.down, amount: 5)]),
    ]
    for (phrase, expected) in table { #expect(g.parse(phrase) == expected, "\(phrase)") }
}

@Test func tabCommandsByNumberNameAndPosition() {
    let cases: [(String, [Action]?)] = [
        ("tab 3", [.goToTab(.number(3))]), ("tab three", [.goToTab(.number(3))]), ("Tab number 12.", [.goToTab(.number(12))]),
        ("switch to tab 4", [.goToTab(.number(4))]), ("go to tab 4", [.goToTab(.number(4))]), ("open tab 99", [.goToTab(.number(99))]),
        ("first tab", [.goToTab(.number(1))]), ("go to the first tab", [.goToTab(.number(1))]),
        ("last tab", [.goToTab(.last)]), ("open the last tab", [.goToTab(.last)]),
        ("switch to the YouTube tab", [.goToTab(.named("YouTube"))]),
        ("go to the my inbox tab.", [.goToTab(.named("my inbox"))]),
        ("open the GitHub tab", [.goToTab(.named("GitHub"))]), ("switch to youtube tab", [.goToTab(.named("youtube"))]),
        ("close the other tabs", [.closeOtherTabs]), ("close other tabs", [.closeOtherTabs]), ("close all other tabs", [.closeOtherTabs]),
        ("list tabs", [.listTabs]), ("list the tabs", [.listTabs]), ("list my tabs", [.listTabs]),
        // Unchanged: other tab phrases, other rules, and what is not a tab command.
        ("tab", [.pressKey(KeyChord(.tab))]), ("new tab", [.pressKey(KeyChord(.t, [.command]))]),
        ("open a new tab", [.pressKey(KeyChord(.t, [.command]))]), ("close tab", [.pressKey(KeyChord(.w, [.command]))]),
        ("close this tab", [.pressKey(KeyChord(.w, [.command]))]),
        ("next tab", [.pressKey(KeyChord(.tab, [.control]))]), ("previous tab", [.pressKey(KeyChord(.tab, [.control, .shift]))]),
        ("go to youtube", [.openURL(URL(string: "https://www.youtube.com")!, app: nil)]), ("open safari", [.openApp("safari")]),
        ("open the new tab", [.pressKey(KeyChord(.t, [.command]))]), ("go to the next tab", [.pressKey(KeyChord(.l, [.command])), .typeText("the next tab"), .pressKey(KeyChord(.return))]),
        ("tab 0", nil), ("tab 100", nil), ("youtube tab", nil), ("tab number", nil),
        ("open chrome and go to the youtube tab", nil), ("open the other tab", [.openApp("the other tab")]),
    ]
    for (spoken, want) in cases { #expect(g.parse(spoken) == want, "\(spoken)") }
}

@Test func textEditingPhrases() {
    func edit(_ e: TextEdit) -> [Action] { [.editText(e, otherwise: nil)] }
    let cmdDelete = [Action.pressKey(KeyChord(.delete))]
    // (spoken, with a text field focused, without one)
    let table: [(String, [Action]?, [Action]?)] = [
        // Units and "last" work with or without a field: the run says "no text field" when there is none.
        ("select word", edit(.select(.word, last: false)), edit(.select(.word, last: false))),
        ("Select the sentence.", edit(.select(.sentence, last: false)), edit(.select(.sentence, last: false))),
        ("select paragraph", edit(.select(.paragraph, last: false)), edit(.select(.paragraph, last: false))),
        ("select the line", edit(.select(.line, last: false)), edit(.select(.line, last: false))),
        ("select the last word", edit(.select(.word, last: true)), edit(.select(.word, last: true))),
        ("select last sentence", edit(.select(.sentence, last: true)), edit(.select(.sentence, last: true))),
        ("delete line", edit(.delete(.line, last: false)), edit(.delete(.line, last: false))),
        ("delete this line", edit(.delete(.line, last: false)), edit(.delete(.line, last: false))),
        ("delete that line", edit(.delete(.line, last: false)), edit(.delete(.line, last: false))),
        ("delete the current line", edit(.delete(.line, last: false)), edit(.delete(.line, last: false))),
        ("delete this word", edit(.delete(.word, last: false)), edit(.delete(.word, last: false))),
        ("delete that word", edit(.delete(.word, last: false)), edit(.delete(.word, last: false))),
        ("select this line", edit(.select(.line, last: false)), edit(.select(.line, last: false))),
        ("select the current word", edit(.select(.word, last: false)), edit(.select(.word, last: false))),
        ("select that paragraph", edit(.select(.paragraph, last: false)), edit(.select(.paragraph, last: false))),
        ("delete the sentence", edit(.delete(.sentence, last: false)), edit(.delete(.sentence, last: false))),
        ("delete the paragraph", edit(.delete(.paragraph, last: false)), edit(.delete(.paragraph, last: false))),
        ("delete last word", edit(.delete(.word, last: true)), edit(.delete(.word, last: true))),
        ("delete the last sentence.", edit(.delete(.sentence, last: true)), edit(.delete(.sentence, last: true))),
        ("go to the end of the line", edit(.caret(.lineEnd)), edit(.caret(.lineEnd))),
        ("go to end of line", edit(.caret(.lineEnd)), edit(.caret(.lineEnd))),
        ("go to the start of the line", edit(.caret(.lineStart)), edit(.caret(.lineStart))),
        ("go to beginning of line", edit(.caret(.lineStart)), edit(.caret(.lineStart))),
        ("go to the end of the document", edit(.caret(.documentEnd)), edit(.caret(.documentEnd))),
        ("go to the bottom of the document", edit(.caret(.documentEnd)), edit(.caret(.documentEnd))),
        ("go to the start of the document", edit(.caret(.documentStart)), edit(.caret(.documentStart))),
        ("go to the top of the document", edit(.caret(.documentStart)), edit(.caret(.documentStart))),
        ("capitalize that", edit(.changeCase(.capitalize)), edit(.changeCase(.capitalize))),
        ("Uppercase that.", edit(.changeCase(.upper)), edit(.changeCase(.upper))),
        ("lowercase that", edit(.changeCase(.lower)), edit(.changeCase(.lower))),
        // Phrases need a focused field, and keep the speaker's casing and words.
        ("select Project Alpha", edit(.selectPhrase("Project Alpha")), nil),
        ("select the old files.", edit(.selectPhrase("the old files")), nil),
        ("delete meeting", edit(.deletePhrase("meeting")), nil),
        ("replace meeting with call", edit(.replace("meeting", with: "call")), nil),
        ("Replace Bob with Alice.", edit(.replace("Bob", with: "Alice")), nil),
        ("replace coffee with tea with milk", edit(.replace("coffee", with: "tea with milk")), nil),   // the first "with" splits
        ("replace the filter with a new one", edit(.replace("the filter", with: "a new one")), nil),
        ("go before the budget", edit(.caretBefore("the budget")), nil),
        ("go after Thanks", edit(.caretAfter("Thanks")), nil),
        // Never an edit: today's rules keep these phrases.
        ("select all", [.pressKey(KeyChord(.a, [.command]))], [.pressKey(KeyChord(.a, [.command]))]),
        ("delete", cmdDelete, cmdDelete), ("delete that", cmdDelete, cmdDelete), ("delete this", cmdDelete, cmdDelete),
        ("delete word", [.pressKey(KeyChord(.delete, [.option]))], [.pressKey(KeyChord(.delete, [.option]))]),
        ("select that", nil, nil), ("select it", nil, nil), ("select", nil, nil), ("delete the", cmdDelete, cmdDelete),   // the filler table, as today
       
        ("replace", nil, nil), ("replace x", nil, nil), ("replace x with", nil, nil), ("replace with y", nil, nil),
        ("replace that with x", nil, nil), ("go before", nil, nil), ("go after the", nil, nil),
        ("select one two three four five six seven eight nine ten eleven twelve thirteen", nil, nil),   // over 12 words
        ("go to the end", [.pressKey(KeyChord(.l, [.command])), .typeText("the end"), .pressKey(KeyChord(.return))],
         [.pressKey(KeyChord(.l, [.command])), .typeText("the end"), .pressKey(KeyChord(.return))]),
        ("go to the end of the page", [.pressKey(KeyChord(.l, [.command])), .typeText("the end of the page"), .pressKey(KeyChord(.return))],
         [.pressKey(KeyChord(.l, [.command])), .typeText("the end of the page"), .pressKey(KeyChord(.return))]),
        ("go to youtube", [.openURL(URL(string: "https://www.youtube.com")!, app: nil)], [.openURL(URL(string: "https://www.youtube.com")!, app: nil)]),
        ("home", [.pressKey(KeyChord(.home))], [.pressKey(KeyChord(.home))]), ("end", [.pressKey(KeyChord(.end))], [.pressKey(KeyChord(.end))]),
        ("copy", [.pressKey(KeyChord(.c, [.command]))], [.pressKey(KeyChord(.c, [.command]))]),
        ("capitalize it", nil, nil), ("capitalize", nil, nil),
    ]
    for (spoken, focused, unfocused) in table {
        #expect(g.parse(spoken, textFocused: true) == focused, "\(spoken) (text field focused)")
        #expect(g.parse(spoken) == unfocused, "\(spoken) (no text field)")
    }
    // The model can never produce an edit: it is the grammar's own.
    #expect(Action.editText(.select(.word, last: false), otherwise: nil).carriesSpokenText == false)
    #expect(Action.editText(.replace("a", with: "b"), otherwise: nil).carriesSpokenText)
}

@Test func mediaAndVolumePhrases() {
    let table: [(String, Action)] = [
        ("play", .media(.play)), ("resume", .media(.play)), ("play the music", .media(.play)),
        ("pause", .media(.pause)), ("pause the video", .media(.pause)), ("pause the music", .media(.pause)),
        ("play pause", .media(.playPause)), ("toggle play", .media(.playPause)),
        ("next track", .media(.next)), ("next song", .media(.next)), ("next video", .media(.next)),
        ("previous track", .media(.previous)), ("previous song", .media(.previous)), ("previous video", .media(.previous)),
        ("full screen video", .media(.fullScreen)), ("video full screen", .media(.fullScreen)),
        ("make the video full screen", .media(.fullScreen)),
        ("exit full screen", .media(.exitFullScreen)), ("leave full screen", .media(.exitFullScreen)),
        ("mute", .volume(.mute(true))), ("mute sound", .volume(.mute(true))),
        ("unmute", .volume(.mute(false))), ("unmute sound", .volume(.mute(false))),
        ("skip ahead", .media(.skip(seconds: 10))), ("skip back", .media(.skip(seconds: -10))),
        ("skip forward", .media(.skip(seconds: 10))), ("skip backward", .media(.skip(seconds: -10))),
        ("skip forward 30 seconds", .media(.skip(seconds: 30))), ("skip backward thirty seconds", .media(.skip(seconds: -30))),
        ("skip ahead one second", .media(.skip(seconds: 1))), ("skip ahead 600 seconds", .media(.skip(seconds: 600))),
        ("volume up", .volume(.by(10))), ("volume down three", .volume(.by(-30))), ("turn it up", .volume(.by(10))),
        ("turn it down 2", .volume(.by(-20))), ("volume up 10", .volume(.by(100))),
        ("volume up fifteen percent", .volume(.by(15))), ("volume down 5 percent", .volume(.by(-5))),
        ("volume 30%", .volume(.set(30))), ("volume up 15%", .volume(.by(15))), ("volume 30 %", .volume(.set(30))),
        ("set volume to 25 percent", .volume(.set(25))), ("volume 40", .volume(.set(40))), ("volume thirty percent", .volume(.set(30))), ("volume 0", .volume(.set(0))),
        ("volume 150 percent", .volume(.set(100))), ("set volume to 25", .volume(.set(25))),
        ("set the volume to fifty percent", .volume(.set(50))),
    ]
    for (said, action) in table { #expect(g.parse(said) == [action], "\(said)") }
    for said in ["volume up 11", "volume up 0", "volume up percent", "volume up 101 percent", "skip ahead 0 seconds",
                 "skip ahead 601 seconds", "skip ahead seconds", "skip", "skip ad", "volume", "volume loud", "set volume"] {
        #expect(g.parse(said) == nil, "\(said)")
    }
    // "play the video" is not a grammar phrase (it can mean clicking the page's Play button): the model gets it.
    #expect(g.parse("play the video") == nil)
    // Older phrases and the stop keep their meaning.
    #expect(g.parse("full screen") == [.pressKey(KeyChord(.f, [.command, .control]))])
    #expect(g.parse("is it playing") == [.checkMedia])
    #expect(g.parse("stop") == nil)
    #expect(g.parse("stop the music") == nil)
}

@Test func systemControlPhrases() {
    let lock = Action.system(.lockScreen), shot = Action.system(.screenshot(.screen))
    let table: [(String, Action)] = [
        ("lock screen", lock), ("lock the screen", lock), ("lock computer", lock), ("lock the mac", lock),
        ("screenshot", shot), ("take a screenshot", shot), ("screenshot screen", shot),
        ("screenshot selection", .system(.screenshot(.selection))), ("screenshot area", .system(.screenshot(.selection))),
        ("screenshot window", .system(.screenshot(.window))),
        ("mission control", .system(.missionControl)), ("open mission control", .system(.missionControl)),
        ("show desktop", .system(.showDesktop)), ("show the desktop", .system(.showDesktop)),
        ("next space", .system(.space(.right))), ("previous space", .system(.space(.left))),
        ("notification center", .system(.notificationCenter)), ("notification centre", .system(.notificationCenter)),
        ("show notifications", .system(.notificationCenter)),
        ("empty trash", .system(.emptyTrash)), ("empty the trash", .system(.emptyTrash)),
        ("open settings for bluetooth", .system(.openSettings(.bluetooth))),
        ("open settings for the wifi", .system(.openSettings(.wifi))),
        ("open sound settings", .system(.openSettings(.sound))), ("privacy and security settings", .system(.openSettings(.privacy))),
        ("login items settings", .system(.openSettings(.loginItems))),
    ]
    for (said, action) in table { #expect(g.parse(said) == [action], "\(said)") }
    // Unchanged phrases, and the stop: none of them is a system command.
    #expect(g.parse("space") == [.pressKey(KeyChord(.space))])
    #expect(g.parse("spotlight") == [.pressKey(KeyChord(.space, [.command]))])
    #expect(g.parse("open system settings") == [.openApp("system settings")])
    #expect(g.parse("open slack settings") == [.openApp("slack settings")])
    #expect(g.parse("open settings") == [.openApp("settings")])
    #expect(CommandGrammar(packs: .builtIns).parse("open settings", frontmost: "com.microsoft.VSCode") == [.pressKey(KeyChord(.comma, [.command]))])
    #expect(g.parse("hide") == [.hideOverlay])
    for said in ["stop", "stop screenshot", "lock screen stop", "empty trash and stop"] { #expect(g.parse(said) == nil, "\(said)") }
}

@Test func settingsPaneNames() {
    let table: [(SettingsPane, [String])] = [
        (.wifi, ["wifi", "wi-fi", "wi fi"]), (.bluetooth, ["bluetooth"]), (.sound, ["sound", "audio"]),
        (.displays, ["display", "displays"]), (.accessibility, ["accessibility"]),
        (.privacy, ["privacy", "privacy and security", "security"]), (.loginItems, ["login items", "startup items"]),
        (.notifications, ["notifications", "notification"]), (.battery, ["battery"]), (.general, ["general"]),
    ]
    #expect(Set(table.map(\.0)) == Set(SettingsPane.allCases))
    for (pane, names) in table {
        for said in names { #expect(SettingsPane.parse(said.split(separator: " ").map(String.init)) == pane, "\(said)") }
    }
    for said in ["slack", "", "settings", "system"] { #expect(SettingsPane.parse(said.split(separator: " ").map(String.init)) == nil, "\(said)") }
    let open: [(String, SettingsPane)] = [
        ("open the settings for wifi", .wifi), ("open settings for display please", .displays),
        ("open settings for privacy & security", .privacy), ("notification settings", .notifications),
    ]
    for (said, pane) in open { #expect(g.parse(said) == [.system(.openSettings(pane))], "\(said)") }
    // An unknown pane after "open settings for" is rejected on the device, never opened and never sent to the model.
    #expect(g.parse("open settings for slack") == nil)
    #expect(g.rejection("open settings for slack") == "no settings pane called slack: say open system settings")
    #expect(g.rejection("open settings for") != nil)
    #expect(g.rejection("open settings for bluetooth") == nil && g.rejection("open system settings") == nil)
    // A compound or long request goes to the model as before, with no rejection.
    for said in ["open settings for bluetooth and turn it off", "open settings for slack and type hello", "open settings for slack bluetooth wifi sound off", "open settings for bluetooth to connect airpods", "open settings for sound to fifty"] {
        #expect(g.parse(said) == nil && g.rejection(said) == nil, "\(said)")
    }
}

@Test func pointerAndPageControlPhrases() {
    func key(_ k: Key, _ m: Set<Modifier> = [.command]) -> [Action] { [.pressKey(KeyChord(k, m))] }
    let drag: [Action] = [.drag(from: .numbered(5), to: .numbered(12))]
    let hold: [Action] = [.moveCursor(.numbered(12)), .pressMouse(.left)]
    let center: [Action] = [.moveCursor(.screenCenter)]
    let table: [(String, [Action]?)] = [
        ("drag 5 to 12", drag), ("drag from 5 to 12", drag), ("drag five to twelve", drag), ("drag two to three", [.drag(from: .numbered(2), to: .numbered(3))]),
        ("click 12 and hold", hold), ("click twelve and hold", hold),
        ("top of page", key(.up)), ("top of the page", key(.up)), ("scroll to the top", key(.up)), ("scroll to top of the page", key(.up)),
        ("bottom of the page", key(.down)), ("scroll to bottom", key(.down)), ("scroll to the bottom of the page", key(.down)),
        ("zoom in", key(.equal)), ("zoom out", key(.minus)), ("actual size", key(.zero)), ("reset zoom", key(.zero)),
        ("move to center", center), ("move to the centre", center), ("move to the center of the screen", center),
        // Unchanged: names, bare directions, the grid, the existing click counts and the caret moves.
        ("drag the file to the trash", nil), ("drag to 12", nil), ("drag 5", nil), ("drag", nil),
        ("click save and hold", [.click(.element(named: "save and hold"), button: .left, count: 1)]),
        ("zoom 35", [.zoomGrid(35)]), ("move to 12", [.moveCursor(.numbered(12))]), ("scroll to the right", nil),
        ("double click 12", [.click(.numbered(12), button: .left, count: 2)]),
        ("right click 12", [.click(.numbered(12), button: .right, count: 1)]),
        ("go to the top of the document", [.editText(.caret(.documentStart), otherwise: nil)]),
    ]
    for (phrase, expected) in table { #expect(g.parse(phrase) == expected, "\(phrase)") }
    // A pack's own phrase still wins in its app.
    #expect(g.parse("scroll to top", frontmost: "com.apple.Terminal") == key(.home))
}
