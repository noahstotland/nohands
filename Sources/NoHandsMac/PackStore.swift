import Foundation
import NoHandsCore

/// The installed packs under `~/.config/nohands/packs/<id>/pack.json`. Folders and files are made, read and replaced
/// with `ConfigFile`'s private-file steps (symlinks refused, 700 and 600, temp file plus rename). A pack is off when
/// its folder holds an empty `disabled` file. Nothing here touches the network.
public struct PackStore: Sendable {
    /// Posted (no payload) after an install, toggle or remove, so a running app can reload.
    public static let changedNotification = Notification.Name("com.nohands.packs-changed")

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/packs")
    }

    public enum StoreError: Error, Equatable, Sendable {
        case badID
        case notInstalled
    }

    public struct Entry: Equatable, Sendable {
        public let id: String
        public let enabled: Bool
        /// The validated pack, nil when `invalidReason` is set.
        public let pack: AppPack?
        public let invalidReason: String?
    }

    public let root: URL
    private let postsChanges: Bool

    public init(root: URL = PackStore.defaultRoot, postsChanges: Bool = true) {
        self.root = root
        self.postsChanges = postsChanges
    }

    /// Validates `data` and writes it as `<id>/pack.json`. Installing an id again replaces the file in place, so the
    /// pack keeps its install order and on/off state. Returns the installed pack.
    @discardableResult
    public func install(_ data: Data) throws -> AppPack {
        let pack = try PackFile.parse(data)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { throw ConfigFile.SaveError.writeFailed(.EIO) }
        try ConfigFile.makePrivateFolder(root.path)
        let folder = folderPath(pack.id)
        let isNew = kind(folder) == nil
        do {
            try ConfigFile.makePrivateFolder(folder)
            let file = folder + "/pack.json"
            _ = try ConfigFile.readRegularFile(file)  // refuses a symlink or odd file already there
            try ConfigFile.replaceFile(file, in: folder, with: data, mode: 0o600)
        } catch {
            if isNew { try? fm.removeItem(atPath: folder) }
            throw error
        }
        announce()
        return pack
    }

    /// Every pack folder in install order (creation time, ties by id). A bad pack is listed with its reason.
    public func list() throws -> [Entry] {
        guard let rootKind = kind(root.path) else { return [] }
        guard rootKind == S_IFDIR else { throw ConfigFile.SaveError.symlink }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let found = names.filter(PackFile.isValidID).compactMap { id -> (Date, Entry)? in
            let folder = folderPath(id)
            guard kind(folder) != nil else { return nil }
            return (created(folder), entry(id, folder))
        }
        return found.sorted { ($0.0, $0.1.id) < ($1.0, $1.1.id) }.map(\.1)
    }

    public func setEnabled(_ id: String, _ enabled: Bool) throws {
        let folder = try existingFolder(id)
        let marker = folder + "/disabled"
        if enabled {
            if unlink(marker) != 0, errno != ENOENT { throw ConfigFile.SaveError.writeFailed(ConfigFile.errnoCode()) }
        } else {
            let fd = open(marker, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            if fd >= 0 { close(fd) } else if errno != EEXIST { throw ConfigFile.SaveError.writeFailed(ConfigFile.errnoCode()) }
        }
        announce()
    }

    /// Deletes `packs/<id>/` and nothing else, after the id pattern check; a symlinked folder is refused.
    public func remove(_ id: String) throws {
        let folder = try existingFolder(id)
        try FileManager.default.removeItem(atPath: folder)
        announce()
    }

    /// The valid, enabled packs in install order: what the grammar loads.
    public func loadEnabled() throws -> [AppPack] {
        try list().compactMap { $0.enabled ? $0.pack : nil }
    }

    private func folderPath(_ id: String) -> String { root.appendingPathComponent(id).path }

    private func existingFolder(_ id: String) throws -> String {
        guard PackFile.isValidID(id) else { throw StoreError.badID }
        let folder = folderPath(id)
        switch kind(folder) {
        case nil: throw StoreError.notInstalled
        case S_IFDIR: return folder
        default: throw ConfigFile.SaveError.symlink
        }
    }

    /// The file type bits at `path` without following a symlink, nil when nothing is there.
    private func kind(_ path: String) -> mode_t? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_mode & S_IFMT : nil
    }

    private func created(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path)[.creationDate]) as? Date) ?? .distantPast
    }

    private func entry(_ id: String, _ folder: String) -> Entry {
        let enabled = kind(folder + "/disabled") == nil
        func bad(_ reason: String) -> Entry { Entry(id: id, enabled: enabled, pack: nil, invalidReason: reason) }
        guard kind(folder) == S_IFDIR else { return bad("folder is a symlink") }
        do {
            guard let data = try ConfigFile.readRegularFile(folder + "/pack.json")?.data else { return bad("pack.json is missing") }
            let pack = try PackFile.parse(data)
            return pack.id == id ? Entry(id: id, enabled: enabled, pack: pack, invalidReason: nil) : bad("id does not match its folder")
        } catch let error as PackError {
            return bad(error.reason)
        } catch {
            return bad("pack.json cannot be read")
        }
    }

    private func announce() {
        guard postsChanges else { return }
        DistributedNotificationCenter.default().postNotificationName(Self.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
