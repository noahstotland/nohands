import Testing
import Foundation
@testable import NoHandsCore

private func pack(_ phrases: [String: [Action]], apps: Set<String> = ["com.x"]) -> AppPack {
    AppPack(id: "p", name: "P", bundleIDs: apps, phrases: phrases)
}
private let cmdN = Action.pressKey(KeyChord(.n, [.command]))

@Test func updateDiffReportsEveryChange() {
    let old = pack(["new note": [cmdN], "pin": [.menuItem("Pin")], "old one": [cmdN]])
    let new = pack(["new note": [.pressKey(KeyChord(.m, [.command]))], "pin": [.menuItem("Pin")], "site": [.openURL(URL(string: "https://a.example.org/")!, app: nil)]],
                   apps: ["com.x", "com.y"])
    let lines = PackDiff.lines(old: old, new: new)
    #expect(lines.contains(#"changed phrase "new note": was command-N, now command-M"#))
    #expect(lines.contains(#"added phrase "site" -> open https://a.example.org/"#))
    #expect(lines.contains(#"removed phrase "old one" -> command-N"#))
    #expect(lines.contains("added app com.y") && lines.contains("added url host a.example.org"))
    #expect(!lines.contains { $0.contains("\"pin\"") })
    #expect(PackDiff.lines(old: old, new: old).isEmpty)
    #expect(PackDiff.lines(old: old, new: pack(["x\u{1B}[2J": [cmdN]])).contains { $0.contains("\\u{1B}") })
}
