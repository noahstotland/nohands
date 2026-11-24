import Foundation
import NoHandsCore

/// What the task loop needs from route memory (NH-46). `routes` is the in-memory list: reading it never touches the
/// disk or the network, and saving, removing and clearing never wait for a file write.
@MainActor public protocol RouteStoring: AnyObject {
    var routes: [Route] { get }
    func save(_ route: Route)
    /// Drops these routes (matched by equality); true when at least one was stored.
    @discardableResult func remove(_ routes: [Route]) -> Bool
    func removeAll()
}

/// The saved routes, kept in memory and in `~/.config/nohands/routes.json` (folder 700, file 600). The file holds goals
/// and the names of what was clicked, never typed or searched text, so it stays on this Mac. It is read once, at
/// launch. A missing, corrupt or unwritable file never stops a task: the list starts empty, the in-memory copy keeps
/// working, and the next save replaces the file. Log lines carry no goals or steps.
@MainActor public final class RouteStore: RouteStoring {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/routes.json")
    }

    public private(set) var routes: [Route]
    private let url: URL
    /// The write in flight. Writes run one after another, in order, so an older list never lands over a newer one.
    private var lastWrite: Task<Void, Never>?

    public init(url: URL = RouteStore.defaultURL) {
        self.url = url
        do {
            routes = RouteMemory.decode(try ConfigFile.readPrivateFile(at: url))
        } catch {
            PipelineLog.warning("routes: could not read the routes file, starting empty", detail: "\(error)")
            routes = []
        }
    }

    public func save(_ route: Route) {
        routes = RouteMemory.saving(route, into: routes)
        write()
    }

    @discardableResult public func remove(_ dropped: [Route]) -> Bool {
        let kept = routes.filter { !dropped.contains($0) }
        guard kept.count != routes.count else { return false }
        routes = kept
        write()
        return true
    }

    /// Empties the list and the file (the file stays, with no routes).
    public func removeAll() {
        routes = []
        write()
    }

    /// Writes the list from a background task; the caller never waits for it.
    private func write() {
        let data: Data
        do { data = try RouteMemory.encoded(routes) } catch {
            PipelineLog.warning("routes: could not encode the routes", detail: "\(error)")
            return
        }
        let url = self.url, previous = lastWrite
        lastWrite = Task.detached {
            await previous?.value
            do { try ConfigFile.writePrivateFile(data, at: url) } catch {
                PipelineLog.warning("routes: could not write the routes file", detail: "\(error)")
            }
        }
    }
}
