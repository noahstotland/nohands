import Foundation

/// Finds the `agent-desktop` binary. NoHands.app is started with `open`, so its PATH is the bare system one and
/// the usual install locations (Homebrew, npm/nvm, bun, volta) have to be searched explicitly.
public enum AgentDesktopLocator {
    static let name = "agent-desktop"

    /// The first candidate that exists and is executable.
    public static func find(configPath: String?, environment: [String: String],
                            home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        candidates(configPath: configPath, environment: environment, home: home).first { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
    }

    /// In priority order: the config path, `$AGENT_DESKTOP_BIN`, Homebrew, `/usr/local/bin`, per-user package
    /// managers, every nvm node version (newest first), then each `PATH` entry.
    public static func candidates(configPath: String?, environment: [String: String], home: URL) -> [URL] {
        var dirs: [URL] = []
        var out: [URL] = []
        if let configPath, !configPath.isEmpty { out.append(URL(fileURLWithPath: configPath)) }
        if let env = environment["AGENT_DESKTOP_BIN"], !env.isEmpty { out.append(URL(fileURLWithPath: env)) }
        dirs += [URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")]
        for d in [".bun/bin", ".volta/bin", ".npm-global/bin", ".local/bin"] { dirs.append(home.appendingPathComponent(d)) }
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? [])
            .filter { $0.hasPrefix("v") }
            .sorted { Self.version($0).lexicographicallyPrecedes(Self.version($1)) }
            .reversed()
        for v in versions { dirs.append(nvm.appendingPathComponent(v).appendingPathComponent("bin")) }
        for p in (environment["PATH"] ?? "").split(separator: ":") where !p.isEmpty { dirs.append(URL(fileURLWithPath: String(p))) }
        out += dirs.map { $0.appendingPathComponent(name) }
        return out
    }

    private static func version(_ s: String) -> [Int] {
        s.dropFirst().split(separator: ".").map { Int($0) ?? 0 }
    }
}
