import Foundation
import Testing
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
