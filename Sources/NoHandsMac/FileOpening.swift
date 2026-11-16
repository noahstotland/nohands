import Foundation
import AppKit
import UniformTypeIdentifiers
import os
import NoHandsCore

/// Where files are found. Spotlight in the app; a fake in tests.
@MainActor public protocol FileSource {
    /// The hits for `query`: below home, no dot or Library path, at most `SpotlightFileSource.limit`, in no set order.
    /// A query that fails or times out is no hits.
    func search(_ query: FileQuery) async -> [FileHit]
}

/// What opening and checking a file need from the Mac.
@MainActor public protocol FileOpening {
    /// The home folder, resolved.
    var home: String { get }
    func facts(forPath path: String) -> FileFacts
    /// Opens the path in its default app, or in Finder when `inFinder`. False when nothing opened it.
    func open(path: String, inFinder: Bool) async -> Bool
}

/// Spotlight over the user's home. Local only: with indexing off, every query finds nothing.
@MainActor public final class SpotlightFileSource: FileSource {
    public static let limit = 200
    private let timeout: Duration
    private let homes: [String]

    public init(timeout: Duration = .seconds(2), home: String = NSHomeDirectory()) {
        self.timeout = timeout
        self.homes = [home, WorkspaceFileOpener.resolved(home) ?? home]
    }

    /// Every word in the display name, and the kind's content types. Words keep out Spotlight's own wildcards.
    static func predicate(_ q: FileQuery) -> NSPredicate {
        var parts = q.words.map { $0.filter { !"*?\"".contains($0) } }.filter { !$0.isEmpty }
            .map { NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemDisplayNameKey, $0) }
        let tree: (String) -> NSPredicate = { NSPredicate(format: "%K == %@", NSMetadataItemContentTypeTreeKey, $0) }
        if let types = q.kind.contentTypes {
            parts.append(NSCompoundPredicate(orPredicateWithSubpredicates: types.map(tree)))
        } else {
            parts.append(NSCompoundPredicate(notPredicateWithSubpredicate: tree("public.folder")))
        }
        // "My last": only things that have been used.
        if q.newestFirst { parts.append(NSPredicate(format: "%K > %@", NSMetadataItemLastUsedDateKey, Date(timeIntervalSince1970: 0) as NSDate)) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: parts)
    }

    public func search(_ q: FileQuery) async -> [FileHit] {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.predicate = Self.predicate(q)
        if q.newestFirst { query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemLastUsedDateKey, ascending: false)] }

        // Gathering ends with a notification; the timer ends it too, and whichever comes first resumes.
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let timeout = self.timeout
        var observer: (any NSObjectProtocol)?
        var timer: Task<Void, Never>?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let finish: @Sendable () -> Void = {
                if resumed.withLock({ let first = !$0; $0 = true; return first }) { continuation.resume() }
            }
            observer = NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { _ in finish() }
            timer = Task { try? await Task.sleep(for: timeout); finish() }
            if !query.start() { finish() }
        }
        timer?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        query.disableUpdates()
        query.stop()

        var hits: [FileHit] = []
        for i in 0..<min(query.resultCount, Self.limit) {
            guard let item = query.result(at: i) as? NSMetadataItem,
                  let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  homes.contains(where: { FileOpenGuard.isListable(path, home: $0) }) else { continue }
            hits.append(FileHit(path: path,
                                name: item.value(forAttribute: NSMetadataItemDisplayNameKey) as? String ?? (path as NSString).lastPathComponent,
                                lastUsed: item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date,
                                modified: item.value(forAttribute: NSMetadataItemFSContentChangeDateKey) as? Date))
        }
        return hits
    }
}

/// Reads the facts the guard decides over, and opens through NSWorkspace.
@MainActor public final class WorkspaceFileOpener: FileOpening {
    public let home: String
    private let foundHome: String

    public init(home: String = NSHomeDirectory()) {
        self.foundHome = home
        self.home = Self.resolved(home) ?? home
    }

    /// The path with every symlink resolved; nil when it does not exist.
    nonisolated static func resolved(_ path: String) -> String? {
        guard let real = realpath(path, nil) else { return nil }
        defer { free(real) }
        return String(cString: real)
    }

    public func facts(forPath path: String) -> FileFacts {
        guard let resolved = Self.resolved(path) else {
            var gone = FileFacts(home: home, foundHome: foundHome, found: path)
            gone.exists = false
            return gone
        }
        var f = FileFacts(home: home, foundHome: foundHome, found: path, resolved: resolved)
        let keys: Set<URLResourceKey> = [.isHiddenKey, .isDirectoryKey, .isRegularFileKey, .isPackageKey, .contentTypeKey, .isReadableKey]
        let values = try? URL(fileURLWithPath: resolved).resourceValues(forKeys: keys)
        f.hidden = values?.isHidden ?? false
        f.isDirectory = values?.isDirectory ?? false
        f.isRegularFile = values?.isRegularFile ?? false
        f.isPackage = values?.isPackage ?? false
        f.readable = values?.isReadable ?? false
        if let type = values?.contentType {
            f.conformsToExecutable = type.conforms(to: .executable)
            f.conformsToContent = type.conforms(to: .content)
        }
        var info = stat()
        if stat(resolved, &info) == 0 { f.hasExecuteBit = info.st_mode & 0o111 != 0 }
        // A link named like a document that points at a script is the script.
        let extensions = [path, resolved].map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        f.fileExtension = extensions.first { FileOpenGuard.deniedExtensions.contains($0) } ?? extensions[0]
        return f
    }

    public func open(path: String, inFinder: Bool) async -> Bool {
        let url = URL(fileURLWithPath: path)
        guard inFinder, let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder") else {
            return !inFinder && NSWorkspace.shared.open(url)
        }
        return (try? await NSWorkspace.shared.open([url], withApplicationAt: finder, configuration: NSWorkspace.OpenConfiguration())) != nil
    }
}
