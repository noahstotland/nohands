import Foundation
import Testing
@testable import NoHandsCore
@testable import NoHandsMac

private func pack(_ id: String, version: String = "1.0.0", phrases: [String: [Action]]) -> AppPack {
    AppPack(id: id, name: "Notes", version: version, author: "Jane", bundleIDs: ["com.apple.Notes"], phrases: phrases)
}
private let newNote: [Action] = [.pressKey(KeyChord(.n, [.command]))]
private let site: [Action] = [.openURL(URL(string: "https://notes.example.org/")!, app: nil)]

/// The summary a person says yes to, shared by `pack add`, `pack install|update` and the app's alert: these lines are what they read.
@Test func theSummaryNamesWhatThePackCanDoAndWhatItReplaces() {
    let new = pack("notes-extras", version: "2.0.0", phrases: ["new note": newNote, "notes site": site])
    let old = pack("notes-extras", version: "1.0.0", phrases: ["new note": newNote])
    let earlier = pack("first", phrases: ["new note": [.pressKey(KeyChord(.m, [.command]))]])
    func entry(_ p: AppPack) -> PackStore.Entry { PackStore.Entry(id: p.id, enabled: true, pack: p, invalidReason: nil) }

    let fresh = PackSummaryText.text(for: new, installed: [])
    #expect(fresh == """
    Notes 2.0.0 by Jane (notes-extras)
      Works in:    com.apple.Notes
      Phrases:     2
      Opens URLs on: notes.example.org
      Says and does:
        "new note" -> command-N
        "notes site" -> open https://notes.example.org/
    """)

    let replaced = PackSummaryText.text(for: new, installed: [entry(earlier), entry(old)], updating: old)
    #expect(replaced.contains("Will not work (an earlier pack has them): \"new note\" (first)"))
    #expect(replaced.contains("Replaces version 1.0.0, already installed."))
    #expect(replaced.hasSuffix("  Changes since 1.0.0:\n    added phrase \"notes site\" -> open https://notes.example.org/\n    added url host notes.example.org"))

    let same = PackSummaryText.text(for: old, installed: [entry(old)], updating: old)
    #expect(same.hasSuffix("  Changes since 1.0.0:\n    none to what it says or does"))
}
