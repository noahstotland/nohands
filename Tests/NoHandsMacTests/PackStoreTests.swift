import Foundation
import Testing
import NoHandsCore
@testable import NoHandsMac

private func packJSON(_ id: String, version: String = "1.0.0", phrase: String = "new note") -> Data {
    Data("""
    {"format":1,"id":"\(id)","name":"Test","version":"\(version)","author":"","bundleIDs":["com.example.\(id)"],
     "commands":[{"phrases":["\(phrase)"],"actions":[{"kind":"press_key","key":"n","modifiers":["command"]}]}]}
    """.utf8)
}

@Test func packStoreInstallListRemove() throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("nohands-packs-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: base) }
    let root = base.appendingPathComponent("home/nohands/packs")
    let store = PackStore(root: root, postsChanges: false)
    func mode(_ path: String) throws -> Int { try fm.attributesOfItem(atPath: path)[.posixPermissions] as! Int }
    func ids() throws -> [String] { try store.list().map(\.id) }

    // Install: private folders and file; installs list in order; re-adding replaces in place and keeps order and off state.
    for id in ["bravo", "alpha"] {
        try store.install(packJSON(id))
        Thread.sleep(forTimeInterval: 0.02)
    }
    #expect(try mode(root.path) == 0o700 && mode(root.path + "/bravo") == 0o700 && mode(root.path + "/bravo/pack.json") == 0o600)
    #expect(try ids() == ["bravo", "alpha"])
    try store.setEnabled("bravo", false)
    try store.install(packJSON("bravo", version: "2.0.0"))
    let listed = try store.list()
    #expect(listed.map(\.id) == ["bravo", "alpha"] && listed[0].pack?.version == "2.0.0" && !listed[0].enabled)
    #expect(try store.loadEnabled().map(\.id) == ["alpha"])
    try store.setEnabled("bravo", true)
    #expect(try store.loadEnabled().map(\.id) == ["bravo", "alpha"])

    // Refusals and a bad pack on disk: nothing changes, the others still load.
    let real = base.appendingPathComponent("real")
    try fm.createDirectory(at: real, withIntermediateDirectories: true)
    let target = real.appendingPathComponent("target.json")
    try packJSON("linked").write(to: target)
    try fm.createSymbolicLink(atPath: root.path + "/linked", withDestinationPath: real.path)
    try fm.createDirectory(atPath: root.path + "/filelink", withIntermediateDirectories: false)
    try fm.createSymbolicLink(atPath: root.path + "/filelink/pack.json", withDestinationPath: target.path)
    try fm.createDirectory(atPath: root.path + "/broken", withIntermediateDirectories: false)
    try Data("{}".utf8).write(to: URL(fileURLWithPath: root.path + "/broken/pack.json"))
    let failures: [(String, () throws -> Void)] = [
        ("linked folder", { try store.install(packJSON("linked")) }),
        ("linked file", { try store.install(packJSON("filelink")) }),
        ("invalid pack", { try store.install(Data("{}".utf8)) }),
        ("bad id", { try store.remove("../alpha") }),
        ("symlinked remove", { try store.remove("linked") }),
        ("missing", { try store.remove("nothere") }),
    ]
    for (name, run) in failures { #expect(throws: (any Error).self, "\(name)") { try run() } }
    #expect(try Data(contentsOf: target) == packJSON("linked") && fm.fileExists(atPath: real.path))
    let entries = try store.list()
    #expect(Set(entries.filter { $0.pack == nil }.map(\.id)) == ["broken", "filelink", "linked"])
    #expect(try store.loadEnabled().map(\.id) == ["bravo", "alpha"])

    // Remove deletes only that folder.
    try store.remove("bravo")
    #expect(!fm.fileExists(atPath: root.path + "/bravo") && fm.fileExists(atPath: root.path + "/alpha/pack.json"))
    #expect(try store.loadEnabled().map(\.id) == ["alpha"])
}
