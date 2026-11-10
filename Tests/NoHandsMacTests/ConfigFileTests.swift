import Foundation
import Testing
import NoHandsCore
@testable import NoHandsMac

@Test func configFileEnsureExists() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("nohands-config-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    func mode(_ url: URL) throws -> Int { try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int }

    // Missing ~/.config, directory and file: all created, private.
    let fresh = root.appendingPathComponent("home/.config/nohands/config.json")
    #expect(try ConfigFile.ensureExists(at: fresh))
    #expect(try Data(contentsOf: fresh) == Data("{}\n".utf8))
    #expect(try mode(fresh) == 0o600)
    #expect(try mode(fresh.deletingLastPathComponent()) == 0o700)

    // An existing file (a user's API key) is never rewritten or re-permissioned.
    let existing = root.appendingPathComponent("existing/config.json")
    try fm.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
    let body = Data(#"{"anthropicAPIKey":"sk-secret"}"#.utf8)
    try body.write(to: existing)
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: existing.path)
    #expect(try !ConfigFile.ensureExists(at: existing))
    #expect(try Data(contentsOf: existing) == body)
    #expect(try mode(existing) == 0o644)

    // A symlink at the path, live or dangling, is not followed or replaced.
    let dir = root.appendingPathComponent("links")
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let target = dir.appendingPathComponent("target.json")
    try body.write(to: target)
    for (name, dest) in [("live.json", target.path), ("dangling.json", dir.appendingPathComponent("missing").path)] {
        let link = dir.appendingPathComponent(name)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: dest)
        #expect(try !ConfigFile.ensureExists(at: link))
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == dest)
    }
    #expect(try Data(contentsOf: target) == body)
    #expect(!fm.fileExists(atPath: dir.appendingPathComponent("missing").path))
}

@Test func configFileSaveAnthropicKey() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("nohands-keysave-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    func mode(_ url: URL) throws -> Int { try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int }
    func noTemps(_ dir: URL, _ name: String) {
        #expect((try? fm.contentsOfDirectory(atPath: dir.path))?.allSatisfy { !$0.hasPrefix(".config.json.") } == true, "\(name)")
    }
    let key = "sk-test-SECRET-123"
    func refuse(_ url: URL, _ expected: ConfigFile.SaveError, _ name: String) {
        do {
            try ConfigFile.saveAnthropicKey(key, at: url)
            Issue.record("\(name): expected a refusal")
        } catch {
            #expect(error as? ConfigFile.SaveError == expected, "\(name)")
            #expect(!"\(error)".contains(key) && !String(describing: error).contains(key), "\(name): error text")
        }
    }

    // Fresh: folder and file are created, private, and the key reads back.
    let fresh = root.appendingPathComponent("home/.config/nohands/config.json")
    try ConfigFile.saveAnthropicKey(key, at: fresh)
    #expect(try mode(fresh) == 0o600 && mode(fresh.deletingLastPathComponent()) == 0o700)
    #expect(try AppConfig.load(from: Data(contentsOf: fresh), environment: [:]).anthropicAPIKey == key)
    noTemps(fresh.deletingLastPathComponent(), "fresh")

    // A wide file and folder are tightened, other keys kept.
    let wide = root.appendingPathComponent("wide/nohands/config.json")
    try fm.createDirectory(at: wide.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"gridRows": 3, "anthropicAPIKey": "old"}"#.utf8).write(to: wide)
    try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: wide.path)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wide.deletingLastPathComponent().path)
    try ConfigFile.saveAnthropicKey(key, at: wide)
    let loaded = try AppConfig.load(from: Data(contentsOf: wide), environment: [:])
    #expect(loaded.anthropicAPIKey == key && loaded.gridRows == 3)
    #expect(try mode(wide) == 0o600 && mode(wide.deletingLastPathComponent()) == 0o700)
    noTemps(wide.deletingLastPathComponent(), "wide")

    // A symlinked file (live or dangling) is refused and its target untouched.
    let links = root.appendingPathComponent("links")
    try fm.createDirectory(at: links, withIntermediateDirectories: true)
    let target = links.appendingPathComponent("target.json")
    let body = Data(#"{"gridRows": 3}"#.utf8)
    try body.write(to: target)
    for (name, dest) in [("live.json", target.path), ("dangling.json", links.appendingPathComponent("missing").path)] {
        let link = links.appendingPathComponent(name)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: dest)
        refuse(link, .symlink, name)
        #expect(try fm.destinationOfSymbolicLink(atPath: link.path) == dest)
    }
    #expect(try Data(contentsOf: target) == body)
    #expect(!fm.fileExists(atPath: links.appendingPathComponent("missing").path))
    noTemps(links, "links")

    // A symlinked folder is refused and the real folder untouched.
    let real = root.appendingPathComponent("real")
    try fm.createDirectory(at: real, withIntermediateDirectories: true)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: real.path)
    let linkedDir = root.appendingPathComponent("linked")
    try fm.createSymbolicLink(atPath: linkedDir.path, withDestinationPath: real.path)
    refuse(linkedDir.appendingPathComponent("config.json"), .symlink, "linked folder")
    #expect(try fm.contentsOfDirectory(atPath: real.path).isEmpty && mode(real) == 0o755)

    // Unparseable JSON and non-objects are left byte for byte.
    for (name, text) in [("garbage", #"{"anthropicAPIKey": "#), ("array", "[]"), ("empty", "")] {
        let url = root.appendingPathComponent("bad-\(name)/config.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        refuse(url, .invalidJSON, name)
        #expect(try Data(contentsOf: url) == Data(text.utf8), "\(name): unchanged")
        noTemps(url.deletingLastPathComponent(), name)
    }
}

@Test func configFileSaveIntentBackend() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("nohands-backendsave-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: root) }
    func mode(_ url: URL) throws -> Int { try fm.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int }
    func noTemps(_ dir: URL, _ name: String) {
        #expect((try? fm.contentsOfDirectory(atPath: dir.path))?.allSatisfy { !$0.hasPrefix(".config.json.") } == true, "\(name)")
    }
    func refuse(_ url: URL, _ expected: ConfigFile.SaveError, _ name: String) {
        do {
            try ConfigFile.saveIntentBackend(.local, at: url)
            Issue.record("\(name): expected a refusal")
        } catch { #expect(error as? ConfigFile.SaveError == expected, "\(name)") }
    }

    // A new file is 600 in a private folder; existing 600 and 640 files keep their mode and every other key.
    let fresh = root.appendingPathComponent("fresh/nohands/config.json")
    try ConfigFile.saveIntentBackend(.claude, at: fresh)
    #expect(try mode(fresh) == 0o600 && mode(fresh.deletingLastPathComponent()) == 0o700)
    #expect(try AppConfig.load(from: Data(contentsOf: fresh), environment: [:]).intentBackend == .claude)
    noTemps(fresh.deletingLastPathComponent(), "fresh")
    for existingMode in [0o600, 0o640] {
        let url = root.appendingPathComponent("mode-\(existingMode)/config.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"anthropicAPIKey": "sk-keep", "gridRows": 3, "intentBackend": "claude"}"#.utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: existingMode], ofItemAtPath: url.path)
        try ConfigFile.saveIntentBackend(.local, at: url)
        let loaded = try AppConfig.load(from: Data(contentsOf: url), environment: [:])
        #expect(loaded.intentBackend == .local && loaded.anthropicAPIKey == "sk-keep" && loaded.gridRows == 3, "\(existingMode)")
        #expect(try mode(url) == existingMode, "\(existingMode): mode kept")
        noTemps(url.deletingLastPathComponent(), "\(existingMode)")
    }

    // A symlinked file or folder is refused and the target untouched.
    let links = root.appendingPathComponent("links")
    try fm.createDirectory(at: links, withIntermediateDirectories: true)
    let target = links.appendingPathComponent("target.json")
    let body = Data(#"{"gridRows": 3}"#.utf8)
    try body.write(to: target)
    let link = links.appendingPathComponent("live.json")
    try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
    refuse(link, .symlink, "linked file")
    #expect(try Data(contentsOf: target) == body)
    let real = root.appendingPathComponent("real")
    try fm.createDirectory(at: real, withIntermediateDirectories: true)
    let linkedDir = root.appendingPathComponent("linked")
    try fm.createSymbolicLink(atPath: linkedDir.path, withDestinationPath: real.path)
    refuse(linkedDir.appendingPathComponent("config.json"), .symlink, "linked folder")
    #expect(try fm.contentsOfDirectory(atPath: real.path).isEmpty)

    // Unparseable JSON is left byte for byte.
    let bad = root.appendingPathComponent("bad/config.json")
    try fm.createDirectory(at: bad.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(#"{"intentBackend": "#.utf8).write(to: bad)
    refuse(bad, .invalidJSON, "invalid json")
    #expect(try Data(contentsOf: bad) == Data(#"{"intentBackend": "#.utf8))
    noTemps(bad.deletingLastPathComponent(), "invalid json")
}
