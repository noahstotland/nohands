import Foundation

/// The highest registry `serial` accepted per registry URL, in `~/.config/nohands/registry-state.json` (mode 600, written
/// with `ConfigFile`'s private-file steps). A replayed older index is refused against it. Holds only URLs and integers.
public struct RegistryState: Sendable {
    public let path: URL

    public static var defaultPath: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/registry-state.json")
    }

    private struct Stored: Codable { var serials: [String: Int] = [:] }

    public init(path: URL = RegistryState.defaultPath) { self.path = path }

    /// The serial recorded for `url`; nil when there is none or the file is missing, unreadable or corrupt.
    public func serial(for url: URL) -> Int? { load().serials[url.absoluteString] }

    /// Records `serial` for `url`, never lowering one already there.
    public func record(serial: Int, for url: URL) throws {
        var stored = load()
        stored.serials[url.absoluteString] = max(serial, stored.serials[url.absoluteString] ?? 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try ConfigFile.writePrivateFile(try encoder.encode(stored), at: path)
    }

    private func load() -> Stored {
        guard let data = (try? ConfigFile.readRegularFile(path.path, limit: 1 << 20))?.data,
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return Stored() }
        return stored
    }
}
