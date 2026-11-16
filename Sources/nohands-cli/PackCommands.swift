import Foundation
import NoHandsCore
import NoHandsMac

/// `nohands-cli pack add|list|remove|builtin`. A pack is data; `add` shows what it can do and installs only on a
/// typed yes. There is no flag to skip the question.
func packCommand(_ args: [String]) {
    let store = PackStore()
    switch (args.first, args.count) {
    case ("add", 2): addPack(path: args[1], store: store)
    case ("list", 1): listPacks(store)
    case ("remove", 2): removePack(args[1], store: store)
    case ("builtin", 2): printBuiltIn(args[1])
    default: usage()
    }
}

private func addPack(path: String, store: PackStore) {
    let data = readPackFile(path)
    let pack: AppPack
    do { pack = try PackFile.parse(data) } catch { fail("not a valid pack: \(error.reason)") }
    let installed: [PackStore.Entry]
    do { installed = try store.list() } catch { fail("error: \(describe(error))") }
    // The set the pack would join: installed packs in order, the new one replacing a pack with its id in place.
    var others = installed.compactMap { $0.enabled && $0.pack?.id != pack.id ? $0.pack : nil }
    if let at = installed.firstIndex(where: { $0.id == pack.id }) {
        others.insert(pack, at: installed[..<at].filter { $0.enabled && $0.pack != nil }.count)
    } else {
        others.append(pack)
    }
    let shadowed = PackSet(installed: others).shadowed.filter { $0.packID == pack.id }
    print(summaryText(PackSummary(pack), id: pack.id, shadowed: shadowed, replaces: installed.first { $0.id == pack.id }))
    print("Install? [y/N] ", terminator: "")
    let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
    if isatty(STDIN_FILENO) == 0 { print() }   // piped input leaves the prompt line open
    guard answer == "y" || answer == "yes" else { fail("not installed") }
    do { try store.install(data) } catch { fail("error: \(describe(error))") }
    print("installed \(pack.id) \(pack.version)")
}

/// The file's bytes, read no further than one byte past the size limit so a huge file is never loaded. Opened once
/// without following a symlink or blocking on a FIFO, then checked with fstat on that same descriptor.
private func readPackFile(_ path: String) -> Data {
    let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
    var info = stat()
    guard fd >= 0, fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
        if fd >= 0 { close(fd) }
        fail("can't read \(path): not a regular file")
    }
    defer { close(fd) }
    let limit = PackFile.maxBytes + 1
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    while data.count < limit {
        let n = read(fd, &buffer, min(buffer.count, limit - data.count))
        if n < 0 { fail("can't read \(path)") }
        if n == 0 { break }
        data.append(contentsOf: buffer[0..<n])
    }
    return data
}

private func summaryText(_ s: PackSummary, id: String, shadowed: [PackSet.Shadowed], replaces: PackStore.Entry?) -> String {
    var lines = ["\(s.name) \(s.version)" + (s.author.isEmpty ? "" : " by \(s.author)") + " (\(id))",
                 "  Works in:    \(s.apps.joined(separator: ", "))",
                 "  Phrases:     \(s.phraseCount)"]
    if !s.urlHosts.isEmpty { lines.append("  Opens URLs on: \(s.urlHosts.joined(separator: ", "))") }
    if !s.openedApps.isEmpty { lines.append("  Opens apps:  \(s.openedApps.joined(separator: ", "))") }
    if !s.overriddenPhrases.isEmpty { lines.append("  Replaces these NoHands phrases in its apps: \(s.overriddenPhrases.joined(separator: ", "))") }
    if !shadowed.isEmpty {
        lines.append("  Will not work (an earlier pack has them): "
                     + shadowed.map { "\"\($0.phrase)\" (\($0.winner))" }.joined(separator: ", "))
    }
    if let replaces {
        lines.append("  Replaces " + (replaces.pack.map { "version \($0.version)" } ?? "an invalid pack") + ", already installed.")
    }
    return lines.joined(separator: "\n")
}

private func listPacks(_ store: PackStore) {
    let entries: [PackStore.Entry]
    do { entries = try store.list() } catch { fail("error: \(describe(error))") }
    guard !entries.isEmpty else { print("no packs installed"); return }
    let set = PackSet(installed: entries.compactMap { $0.enabled ? $0.pack : nil })
    for entry in entries {
        let note = PackMenu.status(phrases: entry.pack?.phrases.count ?? 0, shadowed: set.shadowed.filter { $0.packID == entry.id }.count,
                                   invalidReason: entry.invalidReason)
        print("\(entry.id)  \(entry.pack?.version ?? "-")  \(entry.enabled ? "on" : "off")  \(note)")
    }
}

private func removePack(_ id: String, store: PackStore) {
    do { try store.remove(id) } catch { fail("error: \(describe(error))") }
    print("removed \(id)")
}

private func printBuiltIn(_ id: String) {
    guard let pack = AppPacks.all.first(where: { $0.id == id }) else {
        fail("no built-in pack \"\(id)\" (built-in: \(AppPacks.all.map(\.id).joined(separator: ", ")))")
    }
    print(String(decoding: PackFile.encode(pack), as: UTF8.self))
}

private func describe(_ error: any Error) -> String {
    switch error {
    case let e as PackError: "not a valid pack: \(e.reason)"
    case PackStore.StoreError.badID: "bad pack id (lowercase letters, digits and -)"
    case PackStore.StoreError.notInstalled: "no such installed pack"
    case PackStore.StoreError.tooManyPacks: "too many packs installed (\(PackStore.maxPacks)); remove one first"
    case ConfigFile.SaveError.symlink: "a pack folder is a symlink: replace it with a folder"
    case ConfigFile.SaveError.writeFailed(let code): "write failed (\(code)); check ~/.config/nohands/packs"
    default: "\(error)"
    }
}
