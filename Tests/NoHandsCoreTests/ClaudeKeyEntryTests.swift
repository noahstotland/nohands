import Foundation
import Testing
@testable import NoHandsCore

@Test func claudeKeyEntryMerged() throws {
    let tricky = #"sk-"quoted"\back/slash"#
    let other = #"{"gridColumns": 12, "attentionWord": "computer", "echoCancellation": false, "extra": {"a": [1, 2]}}"#
    let cases: [(name: String, existing: String?, key: String, valid: Bool)] = [
        ("no file", nil, "sk-new", true),
        ("empty object", "{}", "sk-new", true),
        ("other keys kept", other, "sk-new", true),
        ("key replaced", #"{"anthropicAPIKey": "sk-old", "gridRows": 3}"#, "sk-new", true),
        ("quotes and backslashes", "{}", tricky, true),
        ("invalid json", #"{"anthropicAPIKey": "sk-old", "#, "sk-new", false),
        ("array", "[]", "sk-new", false),
        ("empty file", "", "sk-new", false),
    ]
    for c in cases {
        let data = c.existing.map { Data($0.utf8) }
        guard c.valid else {
            #expect(throws: ClaudeKeyEntry.Error.invalidJSON, "\(c.name)") {
                try ClaudeKeyEntry.merged(existing: data, key: c.key)
            }
            continue
        }
        let out = try ClaudeKeyEntry.merged(existing: data, key: c.key)
        #expect(out.last == 0x0A, "\(c.name): trailing newline")
        let object = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any], "\(c.name)")
        #expect(object["anthropicAPIKey"] as? String == c.key, "\(c.name): key")
        if let data, let before = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in before where k != "anthropicAPIKey" {
                #expect(NSDictionary(dictionary: [k: v]).isEqual(to: [k: object[k] as Any]), "\(c.name): \(k) kept")
            }
            #expect(object.count == Set(before.keys).union(["anthropicAPIKey"]).count, "\(c.name): no extra keys")
        }
        let loaded = try AppConfig.load(from: out, environment: [:])
        #expect(loaded.anthropicAPIKey == c.key, "\(c.name): reads back")
    }
    // The untouched values keep their types, not just their text.
    let out = try ClaudeKeyEntry.merged(existing: Data(other.utf8), key: "sk-new")
    let loaded = try AppConfig.load(from: out, environment: [:])
    #expect(loaded.gridColumns == 12 && loaded.attentionWord == "computer" && loaded.echoCancellation == false)
}

@Test func claudeKeyEntryNormalized() {
    let table: [(String, String?)] = [
        ("sk-abc", "sk-abc"), ("  sk-abc \n", "sk-abc"), ("\t\nsk-a b\n", "sk-a b"), ("", nil), (" \n\t ", nil),
    ]
    for (input, expected) in table { #expect(ClaudeKeyEntry.normalized(input) == expected) }
}
