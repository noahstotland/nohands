import Testing
import CoreGraphics
@testable import NoHandsCore

private func el(_ id: Int, _ title: String, ref: String? = nil, y: CGFloat = 0) -> UIElementInfo {
    UIElementInfo(id: id, frame: CGRect(x: 0, y: y, width: 100, height: 20), title: title, role: "AXLink", ref: ref)
}

@Test func matcherPicksExactThenPrefixThenContains() {
    // (words, candidates in walk order, id of the winner, whether `offer` told the walk to stop)
    let table: [(String, [String], Int?, Bool)] = [
        ("raptors", ["Watch the Raptors live", "Raptors vs Celtics", "Raptors"], 3, true),     // exact beats earlier prefix and contains
        ("raptors", ["Watch the Raptors live", "Raptors vs Celtics", "Raptors recap"], 2, false), // prefix beats earlier contains
        ("raptors", ["Raptors game 1", "Raptors game 2"], 1, false),                         // first wins within a tier
        ("raptors", ["a RAPTORS night", "RAPTORS"], 2, true),                                 // case ignored
        ("The Raptors!", ["Raptors"], 1, true),                                              // "the" and trailing punctuation ignored
        ("raptors", ["Celtics", "Bucks"], nil, false),
        ("  ", ["Celtics", ""], nil, false),                                                  // empty words match nothing
    ]
    for (words, texts, winner, stopped) in table {
        var m = PageFind.Matcher(words: words)
        var stop = false
        for (i, t) in texts.enumerated() { stop = m.offer(t, element: el(i + 1, t)) || stop }
        #expect(m.best?.id == winner && stop == stopped, "\(words) in \(texts)")
    }
}

@Test func failureMessageDoesNotTriggerVision() {
    #expect(PageFind.failure("the Raptors game") == "no match for the Raptors game on this page")
    #expect(!PageFind.failure("x").hasPrefix("no element"))
}

@Test func pinFirstPutsTheMatchAtNumberOne() {
    let list = LabelAssigner.assign([el(0, "Home", y: 0), el(1, "Videos", y: 30), el(2, "Raptors", ref: "@s:e9", y: 60), el(3, "About", y: 90)])
    func titles(_ m: [Int: UIElementInfo]) -> [String] { m.keys.sorted().map { m[$0]!.title } }
    let table: [(UIElementInfo, Int, [String])] = [
        (el(77, "raptors", y: 60), 10, ["Raptors", "Home", "Videos", "About"]),                 // by title, case ignored
        (UIElementInfo(id: 0, frame: .zero, title: "other", role: "AXLink", ref: "@s:e9"), 10, ["Raptors", "Home", "Videos", "About"]), // by ref
        (el(77, "Bucks", y: 500), 10, ["Bucks", "Home", "Videos", "Raptors", "About"]),         // absent: inserted
        (el(77, "Bucks", y: 500), 3, ["Bucks", "Home", "Videos"]),                              // absent at the cap: the last drops
        (el(77, "Home", y: 0), 3, ["Home", "Videos", "Raptors"]),                               // already first stays first
    ]
    for (found, limit, expected) in table {
        let pinned = PageFind.pinFirst(list, found: found, limit: limit)
        #expect(titles(pinned) == expected && Set(pinned.keys) == Set(1...expected.count), "\(found.title) limit \(limit)")
    }
    // Two entries with the title: the one under the found frame is the one pinned.
    let twins = LabelAssigner.assign([el(0, "Play", y: 0), el(1, "Play", y: 300)])
    #expect(PageFind.pinFirst(twins, found: el(9, "Play", y: 300), limit: 10)[1]?.id == 1)
}
