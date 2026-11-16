import Testing
import Foundation
@testable import NoHandsCore

private let mail = "com.apple.mail", messages = "com.apple.MobileSMS", chrome = "com.google.Chrome", finder = "com.apple.finder"

@Test func markedPhrasesRouteToConfirmAndOthersExecute() {
    // phrase, frontmost app, the phrase read back when held (nil: runs at once)
    let table: [(String, String?, String?)] = [
        ("send message", mail, "send message"), ("send", mail, "send"), ("delete this email", mail, "delete this email"),
        ("delete conversation", messages, "delete conversation"), ("delete browsing data", chrome, "delete browsing data"),
        ("trash it", finder, "trash it"), ("empty trash", nil, "empty trash"), ("empty the trash", nil, "empty trash"),
        ("undo send", mail, nil), ("next message", mail, nil), ("scroll down", nil, nil),
    ]
    for (phrase, app, held) in table {
        var machine = ModeMachine()
        for routing in [machine.route(phrase, frontmost: app), machine.routeStep(phrase, frontmost: app)] {
            switch routing {
            case .confirm(let h): #expect(h.phrase == held && h.bundleID == (held == "empty trash" ? nil : app), "\(phrase)")
            case .execute: #expect(held == nil, "\(phrase)")
            default: Issue.record("\(phrase) routed to \(routing)")
            }
        }
    }
}

/// The forced rule's reach over the built-ins: every phrase that names a guarded verb (or shares its actions with one)
/// is marked, except the ones that are safe on purpose.
@Test func builtInPhrasesThatNameAGuardedVerbAskFirst() {
    let exempt: Set<String> = ["undo send", "send control c", "remove breakpoint"]
    for pack in AppPacks.all {
        let named = Set(pack.phrases.keys.filter { phrase in
            let words = CommandGrammar.normalize(phrase)
            return words.first != "undo" && IrreversibleGuard.namesVerb(words) && !exempt.contains(phrase)
        })
        let forced = pack.phrases.keys.filter { phrase in named.contains { pack.phrases[$0] == pack.phrases[phrase] } && !exempt.contains(phrase) }
        #expect(Set(forced).isSubset(of: pack.confirms), "\(pack.name): \(Set(forced).subtracting(pack.confirms).sorted())")
        #expect(pack.confirms.isDisjoint(with: exempt))
        #expect(pack.confirms.isSubset(of: Set(pack.phrases.keys)))
    }
}

private func parsed(bundle: String = "com.example.app", _ commands: [[String: Any]]) throws -> AppPack {
    let doc: [String: Any] = ["format": 1, "id": "test-pack", "name": "T", "version": "1", "author": "", "bundleIDs": [bundle], "commands": commands]
    return try PackFile.parse(JSONSerialization.data(withJSONObject: doc))
}
private func cmd(_ phrases: [String], _ chord: String = "n", _ mods: [String] = ["command"], confirm: Any? = nil) -> [String: Any] {
    var c: [String: Any] = ["phrases": phrases, "actions": [["kind": "press_key", "key": chord, "modifiers": mods]]]
    if let confirm { c["confirm"] = confirm }
    return c
}

private func steps(_ phrases: [String], _ actions: [[String: Any]]) -> [String: Any] { ["phrases": phrases, "actions": actions] }

@Test func packFileForcesAndReadsTheConfirmField() throws {
    let send: [String: Any] = ["kind": "press_key", "key": "d", "modifiers": ["command", "shift"]]
    let escape: [String: Any] = ["kind": "press_key", "key": "escape"]
    let deleteItem: [String: Any] = ["kind": "menu_item", "title": "Delete"]
    // commands, bundle, the phrases that ask first
    let table: [([[String: Any]], String, Set<String>)] = [
        ([cmd(["send it", "tidy"])], "com.example.app", ["send it", "tidy"]),                 // a guarded verb
        ([cmd(["move to trash"]), cmd(["undo send"], "z")], "com.example.app", ["move to trash", "undo send"]),   // "trash"; undo frees nothing
        ([cmd(["zap"], "d", ["command", "shift"])], mail, ["zap"]),                             // a marked built-in's actions
        ([steps(["ship it"], [send, escape])], mail, ["ship it"]),                              // a marked built-in's actions, plus more
        ([steps(["undo and delete"], [deleteItem])], "com.example.app", ["undo and delete"]),   // "undo" never frees an irreversible step
        ([cmd(["zap"], "d", ["command", "shift", "function"])], mail, ["zap"]),                // the function modifier changes nothing
        ([steps(["sending now", "send-it"], [escape])], "com.example.app", ["sending now", "send-it"]),   // other forms of a guarded verb
        ([cmd(["send reply"], "return", ["control"]), steps(["go"], [escape, ["kind": "press_key", "key": "return", "modifiers": ["control"]]])],
         "com.example.app", ["send reply", "go"]),                                              // a longer command that holds a forced one
        ([cmd(["zap"], "d", ["command", "shift"])], "com.example.app", []),                     // other app: no match
        ([cmd(["delete it"]), cmd(["tidy up"])], "com.example.app", ["delete it", "tidy up"]),  // same actions as a forced one
        ([cmd(["tidy up"], confirm: true), cmd(["fine"], "m", confirm: false)], "com.example.app", ["tidy up"]),
    ]
    for (commands, bundle, asks) in table {
        #expect(try parsed(bundle: bundle, commands).confirms == asks, "\(commands)")
    }
    let reasons: [(Any, String)] = [
        (false, "confirm false on an irreversible command (it names send, delete or another guarded verb)"),
        ("true", "bad confirm (true or false)"), (1, "bad confirm (true or false)"),
    ]
    for (value, reason) in reasons {
        #expect(throws: PackError("command 1: " + reason)) { try parsed([cmd(["send it"], confirm: value)]) }
    }
    #expect(throws: PackError("command 2: confirm false on an irreversible command (it names send, delete or another guarded verb)")) {
        try parsed([cmd(["delete it"]), cmd(["tidy up"], confirm: false)])
    }
}

@Test func encodeKeepsTheMarkAndSplitsGroupsThatDiffer() throws {
    let n = Action.pressKey(KeyChord(.n, [.command]))
    let pack = AppPack(id: "test-pack", name: "T", bundleIDs: ["com.example.app"], phrases: ["alpha": [n], "beta": [n], "gamma": [n]],
                       confirms: ["alpha", "gamma"])
    #expect(try PackFile.parse(PackFile.encode(pack)).confirms == ["alpha", "gamma"])
}

@Test func summaryAndDiffShowTheMark() {
    let n = Action.pressKey(KeyChord(.n, [.command]))
    let plain = AppPack(id: "p", name: "P", bundleIDs: ["com.x"], phrases: ["tidy": [n], "other": [n]])
    let asking = AppPack(id: "p", name: "P", bundleIDs: ["com.x"], phrases: ["tidy": [n], "other": [n]], confirms: ["tidy"])
    #expect(PackSummary(asking).commandLines == [#""other" -> command-N"#, #""tidy" -> command-N (asks first)"#])
    #expect(PackDiff.lines(old: plain, new: asking) == [#"phrase "tidy" now asks first"#])
    #expect(PackDiff.lines(old: asking, new: plain) == [#"phrase "tidy" no longer asks first"#])
}
