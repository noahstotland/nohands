import Foundation
import Testing
@testable import NoHandsCore

@Test func backendMenuMerged() throws {
    let other = #"{"anthropicAPIKey": "sk-keep", "gridColumns": 12, "echoCancellation": false, "scale": 1.5, "extra": {"a": [1, 2]}}"#
    let cases: [(name: String, existing: String?, choice: BackendChoice, valid: Bool)] = [
        ("no file", nil, .local, true),
        ("empty object", "{}", .claude, true),
        ("other keys kept", other, .local, true),
        ("value replaced", #"{"intentBackend": "claude", "gridRows": 3}"#, .local, true),
        ("invalid json", #"{"intentBackend": "claude", "#, .local, false),
        ("array", "[]", .local, false),
        ("empty file", "", .claude, false),
    ]
    for c in cases {
        let data = c.existing.map { Data($0.utf8) }
        guard c.valid else {
            #expect(throws: ClaudeKeyEntry.Error.invalidJSON, "\(c.name)") { try BackendMenu.merged(existing: data, choice: c.choice) }
            continue
        }
        let out = try BackendMenu.merged(existing: data, choice: c.choice)
        #expect(out.last == 0x0A, "\(c.name): trailing newline")
        let object = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any], "\(c.name)")
        #expect(object["intentBackend"] as? String == c.choice.rawValue, "\(c.name): backend")
        if let data, let before = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in before where k != "intentBackend" {
                #expect(NSDictionary(dictionary: [k: v]).isEqual(to: [k: object[k] as Any]), "\(c.name): \(k) kept")
            }
            #expect(object.count == Set(before.keys).union(["intentBackend"]).count, "\(c.name): no extra keys")
        }
        let loaded = try AppConfig.load(from: out, environment: [:])
        #expect(loaded.intentBackend.rawValue == c.choice.rawValue, "\(c.name): reads back")
    }
    // The untouched values keep their types, not just their text.
    let loaded = try AppConfig.load(from: BackendMenu.merged(existing: Data(other.utf8), choice: .local), environment: [:])
    #expect(loaded.gridColumns == 12 && loaded.echoCancellation == false && loaded.anthropicAPIKey == "sk-keep")
}

@Test func backendMenuTitleAndRows() {
    let claudeTitles = (key: "Claude", none: "Claude (choose Set Claude API key… first)", saved: "Claude (restart NoHands to use the new key)")
    for backend in IntentBackend.allCases {
        for hasKey in [true, false] {
            for saved in [true, false] {
                var config = AppConfig()
                config.intentBackend = backend
                config.anthropicAPIKey = hasKey ? "sk-test" : nil
                let name = "\(backend) key=\(hasKey) saved=\(saved)"
                let effective = config.effectiveBackend
                let expectedTitle = ["Model: Claude", "Model: Local", "Model: Off"][effective == .claude ? 0 : effective == .local ? 1 : 2]
                #expect(BackendMenu.title(config: config) == expectedTitle, "\(name): title")
                let rows = BackendMenu.rows(config: config, keySavedThisSession: saved)
                #expect(rows.map(\.choice) == [.claude, .local], "\(name): order")
                #expect(rows[0].title == (hasKey ? claudeTitles.key : saved ? claudeTitles.saved : claudeTitles.none), "\(name): claude title")
                #expect(rows[0].enabled == hasKey && rows[1].enabled, "\(name): enabled")
                #expect(rows[1].title == "Local model", "\(name): local title")
                #expect(rows[0].checked == (effective == .claude) && rows[1].checked == (effective == .local), "\(name): checks")
            }
        }
    }
}
