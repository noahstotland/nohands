import Foundation
import NoHandsCore

/// Whether agent-desktop is installed, answering and permitted, and which harness that leaves the app with.
public struct HarnessStatus: Equatable, Sendable {
    public var choice: DesktopHarnessChoice
    public var binary: URL?
    public var version: String?
    /// agent-desktop's own report: "granted", "denied", "unknown", …; nil when `status` did not answer.
    public var accessibility: String?

    public init(choice: DesktopHarnessChoice, binary: URL?, version: String?, accessibility: String?) {
        self.choice = choice; self.binary = binary; self.version = version; self.accessibility = accessibility
    }

    public var chosen: HarnessKind {
        guard choice != .native, binary != nil, version != nil else { return .native }
        if choice == .agentDesktop { return .agentDesktop }
        return accessibility == "granted" ? .agentDesktop : .native
    }

    /// The menu line.
    public var text: String {
        switch chosen {
        case .agentDesktop: return "Harness: agent-desktop \(version ?? "")"
        case .native:
            if choice == .native { return "Harness: native (desktopHarness = native)" }
            if binary == nil { return "Harness: native (agent-desktop not found — npm i -g agent-desktop)" }
            if version == nil { return "Harness: native (agent-desktop not responding)" }
            return "Harness: native (agent-desktop: accessibility not granted)"
        }
    }

    /// Locates the binary and asks it for `version` and `status`. `binary`/`client` are injectable for tests.
    public static func probe(config: AppConfig, environment: [String: String] = ProcessInfo.processInfo.environment,
                             binary: URL?? = nil, client: (any DesktopCommandRunning)? = nil) async -> HarnessStatus {
        var status = HarnessStatus(choice: config.desktopHarness, binary: nil, version: nil, accessibility: nil)
        guard config.desktopHarness != .native else { return status }
        let found = binary ?? AgentDesktopLocator.find(configPath: config.agentDesktopPath, environment: environment)
        guard let found else { return status }
        status.binary = found
        let client = client ?? AgentDesktopClient(binary: found, defaultDeadline: .seconds(5))
        let version = await client.run(DesktopCommand.version.argv(headed: false, session: nil), deadline: nil, isObservation: true, environment: [:])
        status.version = version.data?["version"] as? String
        let report = await client.run(DesktopCommand.status.argv(headed: false, session: nil), deadline: nil, isObservation: true, environment: [:])
        status.accessibility = ((report.data?["permissions"] as? [String: Any])?["accessibility"] as? [String: Any])?["state"] as? String
        return status
    }

    /// The harness to run with, or nil for native.
    public func makeHarness(config: AppConfig) -> AgentDesktopHarness? {
        guard chosen == .agentDesktop, let binary else { return nil }
        let client = AgentDesktopClient(binary: binary, defaultDeadline: .milliseconds(config.agentDesktopTimeoutMs))
        return AgentDesktopHarness(client: client, headedFallback: config.agentDesktopHeadedFallback)
    }
}
