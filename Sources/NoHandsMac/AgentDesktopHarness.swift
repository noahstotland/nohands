import Foundation
import NoHandsCore

/// `DesktopHarness` over the agent-desktop CLI.
public final class AgentDesktopHarness: DesktopHarness, @unchecked Sendable {
    public let kind: HarnessKind = .agentDesktop
    private let client: any DesktopCommandRunning
    private let headedFallback: Bool
    private let lock = NSLock()
    private var openSurfaces: [String] = []
    private var sessionID: String?
    /// Headroom over `--timeout-ms` before the child itself is killed.
    static let snapshotGrace: Duration = .milliseconds(1500)
    /// Codes meaning the element the ref pointed at is no longer what it was.
    static let elementChangedCodes: Set<String> = ["STALE_REF", "AMBIGUOUS_TARGET", "SNAPSHOT_NOT_FOUND", "ELEMENT_NOT_FOUND"]

    public init(client: any DesktopCommandRunning, headedFallback: Bool, session: String? = nil) {
        self.client = client
        self.headedFallback = headedFallback
        self.sessionID = session
    }

    /// The active agent-desktop session id, passed as `--session` on every call.
    public var session: String? {
        get { lock.withLock { sessionID } }
        set { lock.withLock { sessionID = newValue } }
    }

    private func run(_ command: DesktopCommand, headed: Bool = false, deadline: Duration? = nil) async -> DesktopEnvelope {
        let session = self.session
        var env: [String: String] = [:]
        if let session { env["AGENT_DESKTOP_SESSION"] = session }
        return await client.run(command.argv(headed: headed, session: session), deadline: deadline,
                                isObservation: command.isObservation, environment: env)
    }

    public func snapshot(app: String, surface: DesktopSurface?, timeoutMs: Int) async -> DesktopSnapshot? {
        let deadline = Duration.milliseconds(timeoutMs) + Self.snapshotGrace
        let first = await run(.snapshot(app: app, windowID: nil, surface: surface, timeoutMs: timeoutMs), deadline: deadline)
        if first.ok { return first.data.flatMap(DesktopSnapshot.parse) }
        guard let error = first.error, error.code == "AMBIGUOUS_TARGET",
              let window = error.candidates.first(where: \.isFocused) ?? error.candidates.first(where: \.visible) ?? error.candidates.first
        else { return nil }
        let second = await run(.snapshot(app: app, windowID: window.id, surface: surface, timeoutMs: timeoutMs), deadline: deadline)
        return second.ok ? second.data.flatMap(DesktopSnapshot.parse) : nil
    }

    public func find(app: String?, surface: DesktopSurface?, name: String) async -> DesktopFindMatch? {
        for exact in [true, false] {
            let e = await run(.find(app: app, surface: surface, name: name, exact: exact))
            if e.ok, let m = e.data.flatMap(DesktopFindMatch.parse) { return m }
        }
        return nil
    }

    public func act(_ command: DesktopCommand) async -> HarnessActionResult {
        var envelope = await run(command)
        if let error = envelope.error, error.notDelivered, headedFallback, !command.needsHeaded,
           Self.worthHeadedRetry(error) {
            envelope = await run(command, headed: true)
        }
        lock.withLock { openSurfaces = envelope.surfaces }
        if envelope.ok { return .delivered(verified: envelope.disposition?.delivery == "delivered_verified") }
        guard let error = envelope.error else { return .failed("agent-desktop failed") }
        if Self.elementChangedCodes.contains(error.code) { return .elementChanged }
        let message = error.message.isEmpty ? error.code : error.message
        return error.notDelivered ? .notDelivered(message) : .failed(message)
    }

    /// A headless path that does not exist or is blocked by policy may exist with `--headed`; a missing element,
    /// a missing permission or a bad argument will not.
    static func worthHeadedRetry(_ error: DesktopError) -> Bool {
        ["ACTION_NOT_SUPPORTED", "POLICY_DENIED", "ACTION_FAILED"].contains(error.code)
    }

    public func read(_ command: DesktopCommand) async -> String? {
        let e = await run(command)
        guard e.ok, let data = e.data else { return nil }
        switch command {
        case .clipboardGet:
            return data["text"] as? String ?? ""
        case .listNotifications:
            let list = data["notifications"] as? [[String: Any]] ?? []
            return list.map { n in
                let app = n["app_name"] as? String ?? "", title = n["title"] as? String ?? "", body = n["body"] as? String ?? ""
                return "\(app): \(title)" + (body.isEmpty ? "" : " — \(body)")
            }.joined(separator: "\n")
        default:
            return DesktopSnapshot.value(data["value"]) ?? DesktopSnapshot.value(data["text"]) ?? ""
        }
    }

    public func listWindows(app: String) async -> [DesktopWindowCandidate] {
        let e = await run(.listWindows(app: app))
        guard e.ok else { return [] }
        // `data` is an array, or an object with `windows`.
        let raw = e.dataArray ?? (e.data?["windows"] as? [[String: Any]]) ?? []
        return raw.compactMap { w in
            guard let id = w["id"] as? String else { return nil }
            return DesktopWindowCandidate(id: id, title: w["title"] as? String ?? "",
                                          isFocused: w["is_focused"] as? Bool ?? false, visible: w["visible"] as? Bool ?? true)
        }
    }

    public func takeOpenSurfaces() -> [String] {
        lock.withLock { defer { openSurfaces = [] }; return openSurfaces }
    }

    public func startSession(name: String) async -> String? {
        let e = await run(.sessionStart(name: name))
        guard e.ok, let id = e.data?["session_id"] as? String, !id.isEmpty else { return nil }
        session = id
        return id
    }

    public func endSession(_ id: String) async {
        session = nil
        _ = await run(.sessionEnd(id: id))
    }
}
