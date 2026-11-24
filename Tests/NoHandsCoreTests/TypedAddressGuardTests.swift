import Foundation
import Testing
@testable import NoHandsCore

@Test func typedAddressNeedsSchemeWwwOrCommonEnding() {
    let accepted = ["youtube.com", "https://example.org/a?b=1", "http://localhost.dev/x", "www.thing", "Youtube.com/@x/videos.",
                    "site.tv"]
    for text in accepted { #expect(WebAddress.typedAddress(text) != nil, "\(text)") }
    let refused = ["hello there", "notes.txt", "main.swift", "apple", "weather", "3.14", "e.g.", "readme.md", "a.zip",
                   "file:///etc/passwd", "javascript:alert(1)", "google maps", ""]
    for text in refused { #expect(WebAddress.typedAddress(text) == nil, "\(text)") }
}

@Test func typedAddressBecomesOpenURLOnlyWhereTheRulesAllow() {
    let url = URL(string: "https://youtube.com/@x/videos")!
    let open: Action = .openURL(url, app: nil)
    let ret: Action = .pressKey(KeyChord(.return, []))
    let cmdL: Action = .pressKey(KeyChord(.l, [.command]))
    let cases: [(goal: String, actions: [Action], expected: [Action])] = [
        // converted, and the Return right after it is dropped
        ("open the latest video", [.typeText("youtube.com/@x/videos"), ret], [open]),
        ("open the latest video", [.typeText("youtube.com/@x/videos"), .wait(ms: 500), ret], [open, .wait(ms: 500), ret]),
        ("open the latest video", [ret, .typeText("youtube.com/@x/videos")], [ret, open]),
        ("open the latest video", [.typeText("youtube.com/@x/videos"), .pressKey(KeyChord(.return, [.shift]))],
         [open, .pressKey(KeyChord(.return, [.shift]))]),
        // ordinary text and names stay typed
        ("open the latest video", [.typeText("hello there")], [.typeText("hello there")]),
        ("open the notes", [.typeText("notes.txt")], [.typeText("notes.txt")]),
        ("open the store", [.typeText("apple")], [.typeText("apple")]),
        // the user asked for text
        ("type youtube.com in the box", [.typeText("youtube.com")], [.typeText("youtube.com")]),
        ("write the link in the email", [.typeText("youtube.com"), ret], [.typeText("youtube.com"), ret]),
        // the step set up a place to type first
        ("open youtube on chrome", [.openApp("Chrome"), cmdL, .typeText("youtube.com"), ret],
         [.openApp("Chrome"), cmdL, .typeText("youtube.com"), ret]),
        ("open youtube", [cmdL, .typeText("youtube.com"), ret], [cmdL, .typeText("youtube.com"), ret]),
        // fields and searches are never rewritten
        ("find it", [.typeInto(.label(2), "youtube.com"), .setValue(.label(2), "youtube.com"), .search("youtube.com")],
         [.typeInto(.label(2), "youtube.com"), .setValue(.label(2), "youtube.com"), .search("youtube.com")]),
    ]
    for c in cases { #expect(TypedAddressGuard.rewrite(c.actions, goal: c.goal) == c.expected, "\(c.goal) \(c.actions)") }
}
