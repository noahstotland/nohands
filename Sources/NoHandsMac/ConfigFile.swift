import Foundation
import NoHandsCore

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

    /// Why a save stopped. Carries nothing from the file or the key, so it is safe to log and show.
    public enum SaveError: Error, Equatable, Sendable {
        case invalidJSON
        case symlink
        case writeFailed(POSIXErrorCode)
    }

    /// Sets `anthropicAPIKey` in the file at `url`, keeping every other key (see `ClaudeKeyEntry.merged`).
    /// The folder is made private (700) and the file is replaced through a private temp file in the same folder
    /// and a rename, so the result is mode 600 and a half-written config is never visible. A symlinked folder or
    /// file, a file that is not a regular file, or unparseable JSON is refused with nothing changed.
    public static func saveAnthropicKey(_ key: String, at url: URL) throws {
        try save(at: url, keepMode: false) { try ClaudeKeyEntry.merged(existing: $0, key: key) }
    }

    /// Sets `intentBackend` in the file at `url`, keeping every other key (see `BackendMenu.merged`). Same steps and
    /// refusals as `saveAnthropicKey`, except an existing file keeps its permission bits; a new file is mode 600.
    public static func saveIntentBackend(_ choice: BackendChoice, at url: URL) throws {
        try save(at: url, keepMode: true) { try BackendMenu.merged(existing: $0, choice: choice) }
    }

    /// Sets `speakFeedback` in the file at `url`, keeping every other key (see `SpeakMenu.merged`). Same steps and
    /// refusals as `saveIntentBackend`.
    public static func saveSpeakFeedback(_ level: SpeakLevel, at url: URL) throws {
        try save(at: url, keepMode: true) { try SpeakMenu.merged(existing: $0, level: level) }
    }

    private static func save(at url: URL, keepMode: Bool, merge: (Data?) throws -> Data) throws {
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { throw SaveError.writeFailed(posixCode(error)) }
        try makePrivateFolder(dir.path)
        let existing = try readRegularFile(url.path)
        let merged: Data
        do { merged = try merge(existing?.data) } catch { throw SaveError.invalidJSON }
        try replaceFile(url.path, in: dir.path, with: merged, mode: keepMode ? (existing?.mode ?? 0o600) : 0o600)
    }

    /// Writes `data` to `url` the way the config is saved: the folder made private (700), the file replaced through a
    /// private temp file and a rename, so it ends mode 600 and is never half written. A symlinked folder or file, or a
    /// file that is not a regular file, is refused with nothing changed. For the command log.
    public static func writePrivateFile(_ data: Data, at url: URL) throws {
        try save(at: url, keepMode: false) { _ in data }
    }

    /// The bytes of the regular file at `url`, or nil when it is missing. A symlink or other kind of file is refused.
    public static func readPrivateFile(at url: URL) throws -> Data? {
        try readRegularFile(url.path)?.data
    }

    static func errnoCode() -> POSIXErrorCode { POSIXErrorCode(rawValue: errno) ?? .EIO }

    private static func posixCode(_ error: Error) -> POSIXErrorCode {
        let ns = error as NSError
        if ns.domain == NSPOSIXErrorDomain, let code = POSIXErrorCode(rawValue: Int32(ns.code)) { return code }
        return (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { POSIXErrorCode(rawValue: Int32($0.code)) } ?? .EIO
    }

    /// Creates the folder at 700, or tightens an existing real folder to 700. A symlink is refused.
    static func makePrivateFolder(_ path: String) throws {
        var st = stat()
        if lstat(path, &st) != 0 {
            guard errno == ENOENT else { throw SaveError.writeFailed(errnoCode()) }
            guard mkdir(path, 0o700) == 0 || errno == EEXIST else { throw SaveError.writeFailed(errnoCode()) }
        } else if (st.st_mode & S_IFMT) == S_IFLNK {
            throw SaveError.symlink
        }
        // O_NOFOLLOW again closes the gap between the lstat and the chmod.
        let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw errno == ELOOP ? SaveError.symlink : SaveError.writeFailed(errnoCode()) }
        defer { close(fd) }
        guard fchmod(fd, 0o700) == 0 else { throw SaveError.writeFailed(errnoCode()) }
    }

    /// The file's bytes and permission bits, or nil when it is missing. A symlink or anything but a regular file is refused.
    /// With a `limit`, no more than that many bytes are read (the caller sees a file longer than it allows by getting `limit`).
    static func readRegularFile(_ path: String, limit: Int? = nil) throws -> (data: Data, mode: mode_t)? {
        // O_NONBLOCK so a FIFO at the path cannot hang the open.
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else {
            switch errno {
            case ENOENT: return nil
            case ELOOP: throw SaveError.symlink
            default: throw SaveError.writeFailed(errnoCode())
            }
        }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { throw SaveError.writeFailed(errnoCode()) }
        guard (st.st_mode & S_IFMT) == S_IFREG else { throw SaveError.writeFailed(.EINVAL) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n < 0 { throw SaveError.writeFailed(errnoCode()) }
            if n == 0 { return (data, st.st_mode & 0o777) }
            data.append(contentsOf: buffer[0..<n])
            if let limit, data.count >= limit { return (data.prefix(limit), st.st_mode & 0o777) }
        }
    }

    /// Writes `data` to a private temp file next to `path`, gives it `mode`, syncs it and renames it over `path`.
    /// The temp file may hold the key, so any failure removes it.
    static func replaceFile(_ path: String, in dir: String, with data: Data, mode: mode_t) throws {
        var template = Array((dir + "/.config.json.XXXXXX").utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { throw SaveError.writeFailed(errnoCode()) }
        let temp = String(decoding: template.dropLast().map { UInt8(bitPattern: $0) }, as: UTF8.self)
        var succeeded = false
        defer { if !succeeded { unlink(temp) } }
        var failure: POSIXErrorCode?
        if fchmod(fd, mode) != 0 { failure = errnoCode() }
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 { failure = errnoCode(); return }
                offset += n
            }
            if fsync(fd) != 0 { failure = errnoCode() }
        }
        if close(fd) != 0, failure == nil { failure = errnoCode() }
        if let failure { throw SaveError.writeFailed(failure) }
        guard rename(temp, path) == 0 else { throw SaveError.writeFailed(errnoCode()) }
        succeeded = true
    }
}
