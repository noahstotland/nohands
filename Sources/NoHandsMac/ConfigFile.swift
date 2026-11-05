import Foundation

/// The user's `~/.config/nohands/config.json`.
public enum ConfigFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/config.json")
    }

    /// Creates `{}` at `url` (mode 600) when nothing is there, and the parent directory (mode 700) if missing.
    /// Returns true if it created the file. An existing file, or a symlink at the path, is never opened,
    /// followed, rewritten or re-permissioned.
    public static func ensureExists(at url: URL) throws -> Bool {
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        // `~/.config` may be missing too: it gets the default mode, only `nohands` is private.
        try fm.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        }
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else {
            if errno == EEXIST { return false }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fd) }
        let bytes = Array("{}\n".utf8)
        let written = write(fd, bytes, bytes.count)
        guard written == bytes.count else {
            let code = written < 0 ? (POSIXErrorCode(rawValue: errno) ?? .EIO) : .EIO
            unlink(url.path)
            throw POSIXError(code)
        }
        return true
    }
}
