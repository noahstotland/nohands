import Foundation
import os
import NoHandsCore

/// Why a registry fetch or a pack download was refused. `userMessage` says what happened and what to do next.
public enum FetchError: Error, Equatable, Sendable {
    case notHTTPS, noConnection, timedOut, signatureFailed, olderThanSeen, downloadMismatch, stateFailed
    case packFailed(String)
    case badResponse(String)

    public var userMessage: String {
        switch self {
        case .notHTTPS: return "Registry URL must be https"
        case .noConnection: return "No connection, installed packs still work"
        case .timedOut: return "Timed out, installed packs still work"
        case .signatureFailed: return "Registry signature failed, nothing installed"
        case .olderThanSeen: return "Registry is older than one already seen, nothing installed"
        case .downloadMismatch: return "Download didn't match the registry, nothing installed"
        case .packFailed(let reason): return "Pack failed checks: \(PackSummary.printable(reason)), nothing installed"
        case .badResponse(let reason): return "Registry sent something unusable (\(PackSummary.printable(reason))), nothing installed"
        case .stateFailed: return "Couldn't save the registry's version, nothing installed"
        }
    }
}

/// The one place a pack is fetched from a registry. It is created only from the Packs menu handlers, the Browse window
/// and `nohands-cli pack search|install|update`, never from the voice pipeline or the task loop (`NetworkBoundaryTests`
/// scans for that). GET only, two fixed headers, no query or body, https with a public host at every hop, size caps
/// read as the bytes arrive, and nothing is written to `packs/`: the caller installs after a yes.
public struct PackFetcher: Sendable {
    static let userAgent = "NoHands-packs/1"
    static let maxRedirects = 3
    static let requestTimeout: TimeInterval = 10
    static let fetchDeadline = Duration.seconds(30)

    let registry: URL
    let trusted: [PackRegistry.TrustedKey]
    let session: URLSession
    let state: RegistryState

    public init(registry: URL, trusting: [PackRegistry.TrustedKey], session: URLSession, state: RegistryState) {
        self.registry = registry
        trusted = trusting
        self.session = session
        self.state = state
    }

    /// Ephemeral: no cache, cookies or credential storage; 10 s per request, 30 s per fetch.
    public static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = requestTimeout
        c.timeoutIntervalForResource = 30
        return URLSession(configuration: c)
    }

    /// A redirect target must be `https` with a public host, like the registry URL itself.
    public static func allowsRedirect(to url: URL) -> Bool { PackFile.isPublicHTTPSURL(url.absoluteString) }

    /// What to offer for a registry entry given the installed version of the same pack id (nil: not installed).
    public enum Decision: Equatable, Sendable {
        case install, update, alreadyInstalled, older, cannotCompare

        /// Why nothing is offered, nil when something is.
        public var userMessage: String? {
            switch self {
            case .install, .update: return nil
            case .alreadyInstalled: return "Already installed"
            case .older: return "Older than installed, not installed"
            case .cannotCompare: return "Installed from a file, can't compare"
            }
        }
    }

    /// The state shown beside a registry entry in a list: empty when it isn't installed.
    public static func stateLabel(_ decision: Decision, entry: RegistryEntry) -> String {
        switch decision {
        case .install: ""
        case .update: "update to \(PackSummary.printable(entry.version))"
        case .alreadyInstalled: "installed"
        case .older: "installed (newer than the registry's)"
        case .cannotCompare: "installed from a file"
        }
    }

    public static func decision(entry: RegistryEntry, installedVersion: String?) -> Decision {
        guard let installedVersion else { return .install }
        guard let new = PackVersion(entry.version), let old = PackVersion(installedVersion) else { return .cannotCompare }
        return new > old ? .update : new == old ? .alreadyInstalled : .older
    }

    /// The registry's verified index. The serial is recorded once the signature has passed; a lower one than recorded is refused.
    public func fetchIndex() async throws(FetchError) -> RegistryIndex {
        guard PackFile.isPublicHTTPSURL(registry.absoluteString) else { throw .notHTTPS }
        let data = try await get(registry, cap: RegistryIndex.maxEnvelopeBytes, tooBig: .badResponse("too large"))
        let index: RegistryIndex
        do throws(RegistryError) { index = try RegistryIndex.parse(envelope: data, trusting: trusted) } catch {
            throw Self.map(error, packStage: false)
        }
        let seen = state.serial(for: registry)
        if let seen, index.serial < seen { throw .olderThanSeen }
        if seen == nil || index.serial > seen! {
            do { try state.record(serial: index.serial, for: registry) } catch { throw .stateFailed }
        }
        return index
    }

    /// The pack's bytes and the pack in them, once they match `entry` (hash, pack rules, id, version, apps).
    public func fetchVerifiedPack(_ entry: RegistryEntry) async throws(FetchError) -> (data: Data, pack: AppPack) {
        guard PackFile.isPublicHTTPSURL(entry.url.absoluteString) else { throw .notHTTPS }
        let data = try await get(entry.url, cap: PackFile.maxBytes, tooBig: .packFailed("file too large (over 64 KiB)"))
        do throws(RegistryError) { return (data, try RegistryIndex.verifyPack(data, against: entry)) } catch {
            throw Self.map(error, packStage: true)
        }
    }

    private static func map(_ error: RegistryError, packStage: Bool) -> FetchError {
        switch error.reason {
        case RegistryError.signatureFailed, RegistryError.unknownKey: return .signatureFailed
        case RegistryError.hashMismatch: return .downloadMismatch
        case let r where r.hasPrefix(RegistryError.packFailedPrefix): return .packFailed(String(r.dropFirst(RegistryError.packFailedPrefix.count)))
        case let r: return packStage ? .packFailed(r) : .badResponse(r)
        }
    }

    // MARK: The request

    private func get(_ url: URL, cap: Int, tooBig: FetchError) async throws(FetchError) -> Data {
        let guardian = RedirectGuard()
        do {
            return try await withThrowingTaskGroup(of: Data?.self) { group in
                group.addTask { try await stream(url, cap: cap, tooBig: tooBig, guardian: guardian) }
                group.addTask { try await Task.sleep(for: Self.fetchDeadline); return nil }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let data = first else { throw FetchError.timedOut }
                return data
            }
        } catch let error as FetchError {
            throw error
        } catch let error as URLError {
            if guardian.refused { throw .badResponse("redirect not allowed") }
            switch error.code {
            case .timedOut: throw .timedOut
            case .cancelled: throw .badResponse("cancelled")
            default: throw .noConnection
            }
        } catch {
            throw .badResponse("cancelled")
        }
    }

    private func stream(_ url: URL, cap: Int, tooBig: FetchError, guardian: RedirectGuard) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: Self.request(url), delegate: guardian)
        if guardian.refused { throw FetchError.badResponse("redirect not allowed") }
        guard let http = response as? HTTPURLResponse else { throw FetchError.badResponse("not an HTTP answer") }
        guard http.statusCode == 200 else { throw FetchError.badResponse("status \(http.statusCode)") }
        if http.expectedContentLength > Int64(cap) { throw tooBig }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > cap { throw tooBig }
        }
        if guardian.refused { throw FetchError.badResponse("redirect not allowed") }
        return data
    }

    /// A GET with the two fixed headers; nothing else is added.
    static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: requestTimeout)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Follows at most 3 redirects, each to an `https` public host, as a plain GET with the fixed headers; anything else
/// is refused and remembered, so the fetch fails even if the response that stopped it looks fine.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    private let seen = OSAllocatedUnfairLock(initialState: (count: 0, refused: false))
    var refused: Bool { seen.withLock { $0.refused } }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let follow = seen.withLock { state -> Bool in
            guard state.count < PackFetcher.maxRedirects, let url = request.url, PackFetcher.allowsRedirect(to: url) else {
                state.refused = true
                return false
            }
            state.count += 1
            return true
        }
        completionHandler(follow ? request.url.map(PackFetcher.request) : nil)
    }
}
