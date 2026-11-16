import Testing
import Foundation
@testable import NoHandsCore

private typealias Doc = [String: Any]
private func cmd(_ phrases: [String], _ actions: [Doc]) -> Doc { ["phrases": phrases, "actions": actions] }
private var cmdQ: Doc { ["kind": "press_key", "key": "q", "modifiers": ["command"]] }
private var cmdN: Doc { ["kind": "press_key", "key": "n", "modifiers": ["command"]] }

private func good() -> Doc {
    ["format": 1, "id": "bear-notes", "name": "Bear", "version": "1.0.0", "author": "Jane Doe", "bundleIDs": ["net.shinyfrog.bear"],
     "commands": [cmd(["new note", "make a note"], [cmdN]),
                  cmd(["archive note"], [["kind": "menu_item", "title": "Archive Note"]]),
                  cmd(["bear help"], [["kind": "open_url", "url": "https://bear.app/faq/"]]),
                  cmd(["quit bear"], [cmdQ])]]
}
private func data(_ edit: (inout Doc) -> Void = { _ in }) -> Data {
    var doc = good()
    edit(&doc)
    return (try? JSONSerialization.data(withJSONObject: doc)) ?? Data()
}
private func commands(_ list: [Doc]) -> (inout Doc) -> Void { { $0["commands"] = list } }

@Test func goodPackParses() throws {
    let pack = try PackFile.parse(data())
    #expect(pack.id == "bear-notes" && pack.name == "Bear" && pack.bundleIDs == ["net.shinyfrog.bear"])
    #expect(pack.phrases["make a note"] == [.pressKey(KeyChord(.n, [.command]))])
    #expect(pack.phrases["bear help"] == [.openURL(URL(string: "https://bear.app/faq/")!, app: nil)])
    #expect(pack.phrases["quit bear"] == [.pressKey(KeyChord(.q, [.command]))])   // a quit phrase that says quit
    let summary = PackSummary(pack)
    #expect(summary.urlHosts == ["bear.app"] && summary.phraseCount == 5 && summary.overriddenPhrases.isEmpty)
}

@Test func badPacksAreRejectedForTheRightReason() {
    var cases: [(String, Data)] = [
        ("too large", data() + Data(repeating: 0x20, count: 70_000)),
        ("invalid JSON", Data("{".utf8)),
        ("unknown key", data { $0["extra"] = 1 }),
        ("missing key", data { $0["author"] = nil }),
        ("unsupported format", data { $0["format"] = 2 }),
        ("unsupported format", data { $0["format"] = true }),
        ("bad id", data { $0["id"] = "Bad_ID" }),
        ("reserved id", data { $0["id"] = "terminal" }),
        ("too long", data { $0["name"] = String(repeating: "n", count: 61) }),
        ("control character", data { $0["author"] = "Jane\u{7}" }),
        ("bundleIDs", data { $0["bundleIDs"] = [String]() }),
        ("bad bundle ID", data { $0["bundleIDs"] = ["a b"] }),
        ("too many commands", data(commands((0..<201).map { cmd(["p\($0)"], [cmdN]) }))),
        ("too many phrases", data(commands((0..<51).map { i in cmd((0..<10).map { "p\(i)x\($0)" }, [cmdN]) }))),
        ("phrase too long", data(commands([cmd(["one two three four five six seven eight nine"], [cmdN])]))),
        ("empty phrase", data(commands([cmd(["?!"], [cmdN])]))),
        ("duplicate phrase", data(commands([cmd(["new note"], [cmdN]), cmd(["New  note."], [cmdN])]))),
        ("too many actions", data(commands([cmd(["go"], Array(repeating: cmdN, count: 9))]))),
        ("no actions", data(commands([cmd(["go"], [])]))),
        ("bad key", data(commands([cmd(["go"], [["kind": "press_key", "key": "nope"]])]))),
        ("bad modifier", data(commands([cmd(["go"], [["kind": "press_key", "key": "n", "modifiers": ["hyper"]]])]))),
        ("unknown key", data(commands([cmd(["go"], [["kind": "menu_item", "title": "X", "extra": 1]])]))),
        ("blocked", data(commands([cmd(["zap"], [cmdQ])]))),
        ("held", data(commands([cmd(["tidy up"], [["kind": "menu_item", "title": "Empty Trash"]])]))),
    ]
    // Kinds the format never allows, URLs it never opens, phrases NoHands keeps for itself.
    for kind in ["type_text", "click", "set_mode", "run_shell", "close_app", "ask_model"] {
        cases.append(("unknown action kind", data(commands([cmd(["go"], [["kind": kind, "text": "x", "target_name": "x"]])]))))
    }
    for url in ["http://bear.app/", "https://user:pw@bear.app/", "javascript:alert(1)", "https://", "https://bear.app/ x"] {
        cases.append(("bad url", data(commands([cmd(["go"], [["kind": "open_url", "url": url]])]))))
    }
    for phrase in ["stop", "Stop!", "never mind", "go to sleep", "wake up", "dictation mode", "stop dictating", "release click", "hide numbers", "cancel", "open cancel"] {
        cases.append(("reserved phrase", data(commands([cmd([phrase], [cmdN])]))))
    }
    for (reason, bytes) in cases {
        do {
            _ = try PackFile.parse(bytes)
            Issue.record("accepted a pack that should fail with \(reason)")
        } catch {
            #expect(error.reason.contains(reason), "wanted \(reason), got \(error.reason)")
        }
    }
}

@Test func builtInPacksRoundTripThroughTheFormat() throws {
    for pack in AppPacks.all {
        #expect(try PackFile.parse(PackFile.encode(pack), reservedIDs: []) == pack, Comment(rawValue: pack.id))
    }
}

@Test func packSetKeepsTheFirstClaimAndListsTheLosers() throws {
    func pack(_ id: String, _ app: String, _ phrases: [String: [Action]]) -> AppPack {
        AppPack(id: id, name: id, bundleIDs: [app], phrases: phrases)
    }
    let enter: [Action] = [.pressKey(KeyChord(.return))], space: [Action] = [.pressKey(KeyChord(.space))]
    let first = pack("first", "x", ["go": enter, "stop": enter])
    let second = pack("second", "x", ["go": space, "other": space])
    let intruder = pack("intruder", "com.apple.Terminal", ["clear": space, "extra": space])
    let grammar = CommandGrammar(packs: PackSet(installed: [first, second, intruder]))
    let set = PackSet(installed: [first, second, intruder])
    #expect(set.shadowed == [.init(packID: "second", phrase: "go", winner: "first"),
                             .init(packID: "intruder", phrase: "clear", winner: "terminal")])
    let cases: [(String, String?, [Action]?)] = [
        ("go", "x", enter),                       // first installed wins
        ("other", "x", space), ("other", "y", nil), ("other", nil, nil),   // only while its app is frontmost
        ("stop", "x", nil),                       // never claimed
        ("clear", "com.apple.Terminal", AppPack.terminal.phrases["clear"]),   // built-in beats installed
        ("extra", "com.apple.Terminal", space),
    ]
    for (phrase, app, expected) in cases {
        #expect(grammar.parse(phrase, frontmost: app) == expected, "\(phrase) in \(app ?? "no app")")
    }
}

@Test func packMenuStatus() {
    for (phrases, shadowed, invalid, line) in [(12, 1, nil, "12 phrases, 1 shadowed"), (1, 0, nil, "1 phrase"),
                                               (0, 0, "unknown action kind", "invalid: unknown action kind")] as [(Int, Int, String?, String)] {
        #expect(PackMenu.status(phrases: phrases, shadowed: shadowed, invalidReason: invalid) == line)
    }
}
