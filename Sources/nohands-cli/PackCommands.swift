import Foundation
import NoHandsCore
import NoHandsMac

/// `nohands-cli pack add|list|remove|builtin|search|install|update`. A pack is data; `add`, `install` and `update` show
/// what it can do and write it only on a typed yes. There is no flag to skip the question. `search`, `install` and
/// `update` are the only ones that reach the network: the registry, and only because you ran them.
func packCommand(_ args: [String]) async {
    let store = PackStore()
    switch (args.first, args.count) {
    case ("add", 2): addPack(path: args[1], store: store)
    case ("search", _): await searchPacks(Array(args.dropFirst()), store: store)
    case ("install", 2): await installFromRegistry(args[1], store: store)
    case ("update", 1), ("update", 2): await updateFromRegistry(args.count == 2 ? args[1] : nil, store: store)
    case ("list", 1): listPacks(store)
    case ("remove", 2): removePack(args[1], store: store)
    case ("builtin", 2): printBuiltIn(args[1])
    default: usage()
    }
}

private func addPack(path: String, store: PackStore) {
    let data = readLimitedFile(path, limit: PackFile.maxBytes)
    let pack: AppPack
    do { pack = try PackFile.parse(data) } catch { fail("not a valid pack: \(error.reason)") }
    let installed = installedPacks(store)
    print(PackSummaryText.text(for: pack, installed: installed))
    guard confirm("Install?") else { fail("not installed") }
    do { try store.install(data) } catch { fail("error: \(PackStore.message(for: error))") }
    print("installed \(pack.id) \(pack.version)")
}

private func installedPacks(_ store: PackStore) -> [PackStore.Entry] {
    do { return try store.list() } catch { fail("error: \(PackStore.message(for: error))") }
}

/// The question and a typed answer; only y or yes is a yes.
private func confirm(_ question: String) -> Bool {
    print("\(question) [y/N] ", terminator: "")
    let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
    if isatty(STDIN_FILENO) == 0 { print() }   // piped input leaves the prompt line open
    return answer == "y" || answer == "yes"
}

/// The file's bytes, read no further than one byte past the size limit so a huge file is never loaded. Opened once
/// without following a symlink or blocking on a FIFO, then checked with fstat on that same descriptor.
func readLimitedFile(_ path: String, limit maxBytes: Int) -> Data {
    let fd = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
    var info = stat()
    guard fd >= 0, fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
        if fd >= 0 { close(fd) }
        fail("can't read \(path): not a regular file")
    }
    defer { close(fd) }
    let limit = maxBytes + 1
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

private func listPacks(_ store: PackStore) {
    let entries: [PackStore.Entry]
    do { entries = try store.list() } catch { fail("error: \(PackStore.message(for: error))") }
    guard !entries.isEmpty else { print("no packs installed"); return }
    let set = PackSet(installed: entries.compactMap { $0.enabled ? $0.pack : nil })
    for entry in entries {
        let note = PackMenu.status(phrases: entry.pack?.phrases.count ?? 0, shadowed: set.shadowed.filter { $0.packID == entry.id }.count,
                                   invalidReason: entry.invalidReason)
        let show = PackSummary.printable
        print("\(show(entry.id))  \(entry.pack.map { show($0.version) } ?? "-")  \(entry.enabled ? "on" : "off")  \(show(note))")
    }
}

private func removePack(_ id: String, store: PackStore) {
    do { try store.remove(id) } catch { fail("error: \(PackStore.message(for: error))") }
    print("removed \(id)")
}

private func printBuiltIn(_ id: String) {
    guard let pack = AppPacks.all.first(where: { $0.id == id }) else {
        fail("no built-in pack \"\(id)\" (built-in: \(AppPacks.all.map(\.id).joined(separator: ", ")))")
    }
    print(String(decoding: PackFile.encode(pack), as: UTF8.self))
}

// MARK: - registry (the network is used only here, because you ran the command)

/// The registry's fetcher, or the reason there is none: nothing is fetched when the registry is unset, off or keyless.
private func registryFetcher() -> PackFetcher {
    let config: AppConfig
    do { config = try loadConfig() } catch { fail("error: config.json is not valid: using the registry needs a readable config") }
    switch RegistryStatus(config: config) {
    case .unavailable(_, let reason): fail(reason)
    case .ready(let url, let keys): return PackFetcher(registry: url, trusting: keys, session: PackFetcher.session(), state: RegistryState())
    }
}

private func fetchIndexOrFail(_ fetcher: PackFetcher) async -> RegistryIndex {
    do throws(FetchError) { return try await fetcher.fetchIndex() } catch { fail(error.userMessage) }
}

private func fetchPackOrFail(_ fetcher: PackFetcher, _ entry: RegistryEntry) async -> (data: Data, pack: AppPack) {
    do throws(FetchError) { return try await fetcher.fetchVerifiedPack(entry) } catch { fail(error.userMessage) }
}

private func installedVersion(of id: String, in installed: [PackStore.Entry]) -> String? {
    installed.first { $0.id == id }?.pack?.version
}

private func searchPacks(_ words: [String], store: PackStore) async {
    let index = await fetchIndexOrFail(registryFetcher())
    let installed = installedPacks(store)
    let wanted = words.map { $0.lowercased() }
    let found = index.packs.filter { entry in
        let haystack = [entry.id, entry.name, entry.description].joined(separator: " ").lowercased()
        return wanted.allSatisfy(haystack.contains)
    }
    guard !found.isEmpty else { print(words.isEmpty ? "the registry lists no packs" : "no pack matches \(words.joined(separator: " "))"); return }
    let show = PackSummary.printable
    for entry in found {
        let state = PackFetcher.stateLabel(PackFetcher.decision(entry: entry, installedVersion: installedVersion(of: entry.id, in: installed)), entry: entry)
        let installedNote = installed.contains { $0.id == entry.id } && state.isEmpty ? "installed (invalid)" : state
        print("\(show(entry.id))  \(show(entry.version))  \(show(entry.name))  [\(entry.bundleIDs.map(show).joined(separator: ", "))]" + (installedNote.isEmpty ? "" : "  \(installedNote)"))
    }
}

private func installFromRegistry(_ id: String, store: PackStore) async {
    let fetcher = registryFetcher()
    let index = await fetchIndexOrFail(fetcher)
    guard let entry = index.packs.first(where: { $0.id == id }) else { fail("no pack \"\(PackSummary.printable(id))\" in the registry") }
    let installed = installedPacks(store)
    switch PackFetcher.decision(entry: entry, installedVersion: installedVersion(of: id, in: installed)) {
    case .install: break
    case .update: fail("\(id) is already installed; run: nohands-cli pack update \(id)")
    case let other: fail(other.userMessage ?? "not installed")
    }
    let (data, pack) = await fetchPackOrFail(fetcher, entry)
    print(PackSummaryText.text(for: pack, installed: installed))
    guard confirm("Install?") else { fail("not installed") }
    do { try store.install(data) } catch { fail("error: \(PackStore.message(for: error))") }
    print("installed \(pack.id) \(pack.version)")
}

private func updateFromRegistry(_ id: String?, store: PackStore) async {
    let installed = installedPacks(store)
    if let id, !installed.contains(where: { $0.id == id }) { fail("\(PackSummary.printable(id)) is not installed") }
    let fetcher = registryFetcher()
    let index = await fetchIndexOrFail(fetcher)
    var offered = 0
    for entry in index.packs where id == nil || entry.id == id {
        guard let old = installed.first(where: { $0.id == entry.id })?.pack else { continue }
        let decision = PackFetcher.decision(entry: entry, installedVersion: old.version)
        guard decision == .update else {
            if id != nil { print(decision.userMessage ?? "nothing to update") }
            continue
        }
        offered += 1
        let (data, pack) = await fetchPackOrFail(fetcher, entry)
        print(PackSummaryText.text(for: pack, installed: installed, updating: old))
        guard confirm("Update?") else { print("not updated"); continue }
        do { try store.install(data) } catch { fail("error: \(PackStore.message(for: error))") }
        print("updated \(pack.id) to \(pack.version)")
    }
    if id == nil && offered == 0 { print("all packs are up to date") }
    if let id, offered == 0, !index.packs.contains(where: { $0.id == id }) { print("\(PackSummary.printable(id)) is not in the registry") }
}
