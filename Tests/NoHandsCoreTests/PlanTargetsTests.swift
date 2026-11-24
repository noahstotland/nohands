import Testing
import Foundation
import CoreGraphics
@testable import NoHandsCore

/// Rows from real element lists captured in Chrome on 2026-11-09 (native walk, cap raised to 200), trimmed to the
/// page chrome, the sidebar and the first cards. Format: `n role (x,y wxh) title`.
private let videoTab = """
 12  AXPopUpButton  (92,38 28x28)  Tab search
 13  AXRadioButton  (114,32 109x41)  noahstotland/nohands: Control your Mac entirely with your voice: on-device speech recognition, a fast command grammar, a
 49  AXButton  (16,119 128x1)  Skip navigation
 50  AXLink  (56,119 131x56)  YouTube Premium Home
 51  AXButton  (974,127 64x40)  Search
 52  AXButton  (1054,127 40x40)  Search with your voice
 53  AXButton  (1283,127 103x40)  Create
 54  AXButton  (1394,127 40x40)  Notifications
 55  AXPopUpButton  (1442,130 54x34)  Account menu
 56  AXCheckBox  (24,135 24x24)  Guide
 57  AXComboBox  (455,135 515x24)  Search
 58  AXLink  (12,187 204x40)  Home
 59  AXLink  (12,227 204x40)  Shorts
 60  AXLink  (12,292 204x40)  Subscriptions
 61  AXLink  (12,332 204x40)  ApparentlyJack. New content available.
 62  AXLink  (12,372 204x40)  Feer. New content available.
 63  AXLink  (12,412 204x40)  Xander Budnick. New content available.
 64  AXLink  (12,452 204x40)  Channel 5 with Andrew Callaghan. New content available.
 68  AXLink  (12,492 204x40)  Indigo Traveller
 70  AXLink  (12,532 204x40)  Daniel Li. New content available.
 71  AXRadioButton  (341,563 48x49)  Home
 72  AXRadioButton  (413,563 50x49)  Videos
 73  AXRadioButton  (486,563 49x49)  Shorts
 74  AXRadioButton  (558,563 70x49)  Playables
 75  AXRadioButton  (651,563 61x49)  Playlists
 78  AXLink  (12,572 204x40)  Jef. New content available.
 79  AXButton  (12,612 204x40)  Show more
 80  AXRadioButton  (339,627 64x33)  Latest
 83  AXLink  (12,677 204x40)  You
 84  AXLink  (12,717 204x40)  Your channel
 89  AXLink  (331,891 348x44)  I finally saw quantum mechanics with my own eyes... (It's spookier than I expected) 1 hour, 5 minutes
 90  AXButton  (648,885 41x40)  More actions
 91  AXLink  (694,891 348x44)  No device could prove Einstein wrong... until now 34 minutes
 92  AXButton  (1012,885 40x40)  More actions
 93  AXLink  (1058,891 347x44)  Fiber Optics are so much cooler than I thought 34 minutes
 94  AXButton  (1375,885 40x40)  More actions
 95  AXLink  (12,917 204x40)  Your videos
 96  AXLink  (12,957 204x25)  Downloads
"""

private let searchPage = """
 49  AXTextArea  (207,146 702x50)  Search
 50  AXButton  (1360,151 40x40)  Share
 51  AXButton  (1404,151 40x40)  Google apps
 52  AXPopUpButton  (1452,151 40x40)  Google Account: Noah Stotland (noahstotland@gmail.com), Google membership
 53  AXLink  (50,155 92x34)  Go to Google Home
 54  AXButton  (909,157 44x28)  Clear
 55  AXButton  (958,159 40x24)  Search by voice
 56  AXButton  (998,159 40x24)  Search by image
 57  AXLink  (11,177 110x44)  Skip to main content
 58  AXLink  (194,207 79x48)  AI Mode
 59  AXLink  (272,207 41x48)  All
 60  AXLink  (313,207 87x48)  Shopping
 61  AXLink  (399,207 108x48)  Short videos
 62  AXLink  (507,207 72x48)  Images
 63  AXLink  (578,207 69x48)  Videos
 64  AXLink  (646,207 74x48)  Forums
 65  AXButton  (719,207 76x48)  More filters
 66  AXButton  (795,207 77x48)  Tools
 67  AXButton  (206,608 1100x50)  Show more AI Overview
 68  AXLink  (206,715 349x71)  Beginner Sourdough Starter Recipe The Clever Carrot https://www.theclevercarrot.com › 2019/03 › beginner-...
 69  AXButton  (549,733 35x20)  About this result
 70  AXLink  (640,814 70x16)  Read more
 71  AXLink  (206,885 340x71)  Sourdough Starter Recipe King Arthur Baking https://www.kingarthurbaking.com › recipes › sourdoug...
 72  AXButton  (553,903 35x20)  About this result
"""

private func parse(_ text: String) -> (elements: [ObservedElement], frames: [Int: CGRect]) {
    var elements: [ObservedElement] = [], frames: [Int: CGRect] = [:]
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, let n = Int(parts[0]) else { continue }
        let rest = parts[2].trimmingCharacters(in: .whitespaces)   // "(x,y wxh)  title"
        let close = rest.firstIndex(of: ")")!
        let nums = rest[rest.index(after: rest.startIndex)..<close].split(whereSeparator: { ", x".contains($0) }).compactMap { Double($0) }
        let title = rest[rest.index(after: close)...].trimmingCharacters(in: .whitespaces)
        elements.append(ObservedElement(number: n, role: String(parts[1].dropFirst(2)).lowercased(), title: title))
        frames[n] = CGRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
    }
    return (elements, frames)
}

@Test func firstItemPicksTheContentLinkOnRealPages() {
    let yt = parse(videoTab), g = parse(searchPage)
    func title(_ n: Int?, _ list: [ObservedElement]) -> String? { list.first { $0.number == n }?.title }
    // Sidebar links ("Jef. New content available.") come first in the native order and have three or more words.
    let cardStart = "I finally saw quantum mechanics"
    #expect(title(PlanTargets.firstItem(after: nil, in: yt.elements, frames: yt.frames), yt.elements)?.hasPrefix(cardStart) == true)
    #expect(title(PlanTargets.firstItem(after: "Videos", in: yt.elements, frames: yt.frames), yt.elements)?.hasPrefix(cardStart) == true)
    #expect(title(PlanTargets.firstItem(after: "Latest", in: yt.elements, frames: yt.frames), yt.elements)?.hasPrefix(cardStart) == true)
    // Skip links and the logo link are wide enough for three words but not for content.
    #expect(title(PlanTargets.firstItem(after: nil, in: g.elements, frames: g.frames), g.elements)?.hasPrefix("Beginner Sourdough Starter Recipe") == true)
    #expect(title(PlanTargets.firstItem(after: "Tools", in: g.elements, frames: g.frames), g.elements)?.hasPrefix("Beginner Sourdough") == true)
}

@Test func firstItemHandsOverWhenNothingQualifies() {
    let yt = parse(videoTab)
    let cards = Set(yt.elements.filter { $0.title.contains("minutes") || $0.title.contains("hour") }.map(\.number))
    let noCards = yt.elements.filter { !cards.contains($0.number) }
    var offscreen = yt.elements
    for i in offscreen.indices where cards.contains(offscreen[i].number) { offscreen[i].states = ["offscreen"] }
    var notLinks = yt.elements
    for i in notLinks.indices where cards.contains(notLinks[i].number) { notLinks[i].role = "button" }
    let cases: [(String, [ObservedElement], [Int: CGRect], String?)] = [
        ("no frames", yt.elements, [:], nil),
        ("only the sidebar", noCards, yt.frames, nil),
        ("cards offscreen", offscreen, yt.frames, nil),
        ("cards not links", notLinks, yt.frames, nil),
        ("anchor not on screen", yt.elements, yt.frames, "Playables of Doom"),
        ("anchor after the cards", yt.elements, yt.frames, "Downloads"),
    ]
    for (why, list, frames, after) in cases { #expect(PlanTargets.firstItem(after: after, in: list, frames: frames) == nil, "\(why)") }
}

@Test func clickPrefersExactTitlesAndSkipsTheMenuBar() {
    let list = [
        ObservedElement(number: 1, role: "menubaritem", title: "Edit"),
        ObservedElement(number: 2, role: "button", title: "Edit profile settings"),
        ObservedElement(number: 3, role: "button", title: "Edit"),
        ObservedElement(number: 4, role: "link", title: "Café Menu"),
        ObservedElement(number: 5, role: "AXMenuBarItem", title: "Window"),
    ]
    let cases: [(String, Int?)] = [("edit", 3), ("Edit profile", 2), ("cafe menu", 4), ("window", nil), ("nothing like it", nil), ("", nil)]
    for (text, want) in cases { #expect(PlanTargets.click(text: text, in: list) == want, "\(text)") }
}
