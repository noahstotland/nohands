import Foundation
import CryptoKit
import Testing
@testable import NoHandsCore
@testable import NoHandsMac

private let keyBytes = Curve25519.Signing.PrivateKey().rawRepresentation
private func privateKey(_ raw: Data = keyBytes) -> Curve25519.Signing.PrivateKey { try! Curve25519.Signing.PrivateKey(rawRepresentation: raw) }
private let trusted = [PackRegistry.TrustedKey(publicKey: privateKey().publicKey.rawRepresentation)]
private let registry = URL(string: "https://packs.example.org/index.json")!
private let packBytes = Data(#"{"format":1,"id":"notes-extras","name":"Notes","version":"1.2.0","author":"","bundleIDs":["com.apple.Notes"],"commands":[{"phrases":["new note"],"actions":[{"kind":"press_key","key":"n","modifiers":["command"]}]}]}"#.utf8)

private func envelope(serial: Int = 7, signedBy raw: Data = keyBytes, pack: Data = packBytes) -> Data {
    let entry: [String: Any] = ["id": "notes-extras", "name": "Notes", "author": "", "version": "1.2.0", "description": "", "bundleIDs": ["com.apple.Notes"],
                                "url": "https://packs.example.org/n.json", "sha256": SHA256.hash(data: pack).map { String(format: "%02x", $0) }.joined()]
    let index = try! JSONSerialization.data(withJSONObject: ["format": 1, "serial": serial, "packs": [entry]] as [String: Any])
    let signature = try! privateKey(raw).signature(for: PackRegistry.signingInput(index))
    return try! JSONSerialization.data(withJSONObject: ["format": 1, "keyID": trusted[0].keyID, "index": index.base64EncodedString(),
                                                        "signature": signature.base64EncodedString()] as [String: Any])
}

private struct Rig {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nohands-fetch-\(UUID().uuidString)")
    var state: RegistryState { RegistryState(path: dir.appendingPathComponent("registry-state.json")) }
    var store: PackStore { PackStore(root: dir.appendingPathComponent("packs"), postsChanges: false) }
    func fetcher(_ url: URL = registry) -> PackFetcher { PackFetcher(registry: url, trusting: trusted, session: makeSession(), state: state) }
    func untouched() -> Bool { (try? store.list())?.isEmpty == true && !FileManager.default.fileExists(atPath: dir.appendingPathComponent("packs").path) }
}

extension ClaudeIntentResolverTests {
    @Test func fetchedIndexAndPackAreCheckedAndRequestsCarryOnlyFixedHeaders() async throws {
        let rig = Rig(); defer { try? FileManager.default.removeItem(at: rig.dir) }
        StubProtocol.reset { $0.url?.path == "/index.json" ? (200, envelope()) : (200, packBytes) }
        let fetcher = rig.fetcher()
        let index = try await fetcher.fetchIndex()
        let (data, pack) = try await fetcher.fetchVerifiedPack(index.packs[0])
        #expect(index.serial == 7 && rig.state.serial(for: registry) == 7 && pack.id == "notes-extras" && data == packBytes)
        #expect(StubProtocol.requests.count == 2 && StubProtocol.bodies.allSatisfy(\.isEmpty))
        let allowed: Set<String> = ["User-Agent", "Accept", "Accept-Encoding", "Accept-Language"]
        for r in StubProtocol.requests {
            #expect(r.httpMethod == "GET" && r.url?.query == nil && r.httpBody == nil)
            #expect(r.value(forHTTPHeaderField: "User-Agent") == "NoHands-packs/1" && r.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(Set((r.allHTTPHeaderFields ?? [:]).keys).isSubset(of: allowed), "\(r.allHTTPHeaderFields ?? [:])")
        }
        #expect(rig.untouched())
    }

    @Test func everyFailureMapsToItsMessageAndWritesNothing() async throws {
        let table: [(String, (Rig) throws -> Void, (URLRequest) -> (Int, Data)?, URLError?, FetchError)] = [
            ("bad signature", { _ in }, { _ in (200, envelope(signedBy: Curve25519.Signing.PrivateKey().rawRepresentation)) }, nil, .signatureFailed),
            ("older serial", { try $0.state.record(serial: 9, for: registry) }, { _ in (200, envelope(serial: 7)) }, nil, .olderThanSeen),
            ("over cap", { _ in }, { _ in (200, Data(repeating: 0x20, count: RegistryIndex.maxEnvelopeBytes + 1)) }, nil, .badResponse("too large")),
            ("status", { _ in }, { _ in (503, Data()) }, nil, .badResponse("status 503")),
            ("timeout", { _ in }, { _ in nil }, URLError(.timedOut), .timedOut),
            ("offline", { _ in }, { _ in nil }, URLError(.notConnectedToInternet), .noConnection),
        ]
        for (name, setup, handler, failure, expected) in table {
            let rig = Rig(); defer { try? FileManager.default.removeItem(at: rig.dir) }
            try setup(rig)
            let before = rig.state.serial(for: registry)
            StubProtocol.reset(handler); StubProtocol.failWith = failure
            do throws(FetchError) { _ = try await rig.fetcher().fetchIndex(); Issue.record("\(name) accepted") } catch { #expect(error == expected, "\(name): \(error)") }
            #expect(rig.state.serial(for: registry) == before && rig.untouched(), "\(name)")
        }
    }

    @Test func registryUrlsThatAreNotPublicHttpsSendNoRequest() async {
        for url in ["http://packs.example.org/i.json", "https://10.0.0.1/i.json", "https://localhost/i.json", "https://me@packs.example.org/i.json"] {
            StubProtocol.reset { _ in (200, envelope()) }
            do throws(FetchError) { _ = try await Rig().fetcher(URL(string: url)!).fetchIndex(); Issue.record("\(url) fetched") } catch { #expect(error == .notHTTPS, "\(url)") }
            #expect(StubProtocol.requests.isEmpty, "\(url)")
        }
    }

    @Test func redirectsToUnsafeAddressesOrWithoutEndAreRefused() async {
        let ok = ["https://cdn.example.org/i.json"], bad = ["http://cdn.example.org/", "https://192.168.0.1/", "https://localhost/", "https://u@cdn.example.org/"]
        #expect(ok.allSatisfy { PackFetcher.allowsRedirect(to: URL(string: $0)!) } && !bad.contains { PackFetcher.allowsRedirect(to: URL(string: $0)!) })
        for target in ["http://cdn.example.org/i.json", "https://192.168.0.1/i.json", "https://cdn.example.org/loop"] {
            StubProtocol.reset { _ in (200, envelope()) }
            StubProtocol.redirectTo = URL(string: target)
            do throws(FetchError) { _ = try await Rig().fetcher().fetchIndex(); Issue.record("\(target) followed") } catch { #expect(error == .badResponse("redirect not allowed"), "\(target): \(error)") }
            #expect(StubProtocol.requests.count <= 4, "\(target)")
        }
    }

    @Test func packDownloadIsHeldToTheIndexEntryAndTheSizeCap() async throws {
        StubProtocol.reset { _ in (200, envelope()) }
        let entry = try await Rig().fetcher().fetchIndex().packs[0]
        let tooBig = Data(repeating: 0x20, count: PackFile.maxBytes + 1)
        let table: [(Data, FetchError)] = [(Data(packBytes.reversed()), .downloadMismatch), (tooBig, .packFailed("file too large (over 64 KiB)"))]
        for (body, expected) in table {
            StubProtocol.reset { _ in (200, body) }
            do throws(FetchError) { _ = try await Rig().fetcher().fetchVerifiedPack(entry); Issue.record("accepted") } catch { #expect(error == expected) }
        }
    }
}

@Test func installDecisionAndMessages() throws {
    let entry = try RegistryIndex.parse(envelope: envelope(), trusting: trusted).packs[0]   // version 1.2.0
    let table: [(String?, PackFetcher.Decision)] = [(nil, .install), ("1.1", .update), ("1.2", .alreadyInstalled), ("1.10", .older), ("beta", .cannotCompare)]
    for (installed, want) in table { #expect(PackFetcher.decision(entry: entry, installedVersion: installed) == want, "\(installed ?? "nil")") }
    let messages: [(FetchError, String)] = [
        (.noConnection, "No connection, installed packs still work"), (.timedOut, "Timed out, installed packs still work"),
        (.signatureFailed, "Registry signature failed, nothing installed"), (.olderThanSeen, "Registry is older than one already seen, nothing installed"),
        (.downloadMismatch, "Download didn't match the registry, nothing installed"), (.packFailed("no commands"), "Pack failed checks: no commands, nothing installed"),
        (.notHTTPS, "Registry URL must be https"),
    ]
    for (error, text) in messages { #expect(error.userMessage == text) }
    #expect(PackFetcher.Decision.older.userMessage == "Older than installed, not installed")
}

@Test func registryStateKeepsHighestSerialPrivatelyAndReadsCorruptFileAsEmpty() throws {
    let rig = Rig(); defer { try? FileManager.default.removeItem(at: rig.dir) }
    #expect(rig.state.serial(for: registry) == nil)
    try rig.state.record(serial: 5, for: registry)
    try rig.state.record(serial: 3, for: URL(string: "https://other.example.org/i.json")!)
    #expect(rig.state.serial(for: registry) == 5 && rig.state.serial(for: URL(string: "https://other.example.org/i.json")!) == 3)
    let path = rig.dir.appendingPathComponent("registry-state.json").path
    #expect(try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int == 0o600)
    try Data("{nope".utf8).write(to: URL(fileURLWithPath: path))
    #expect(rig.state.serial(for: registry) == nil)
}
