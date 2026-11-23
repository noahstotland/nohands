import Foundation
import NoHandsCore

/// The last 50 commands, kept in memory and in `~/.config/nohands/command-log.json` (folder 700, file 600). The file
/// holds spoken phrases and typed text, so it stays on this Mac and is never sent anywhere. A missing, corrupt or
/// unwritable file never stops anything: the log starts empty and the in-memory copy keeps working.
@MainActor public final class CommandLogStore {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/nohands/command-log.json")
    }

    public private(set) var log: CommandLog
    /// Called after each append, so the menu and an open window can refresh.
    public var onChange: (() -> Void)?
    /// False turns recording off: `append` does nothing. Entries already in the log stay until `clear()`.
    public var isRecording = true

    private let url: URL
    /// The write in flight. Writes run one after another, in order, so an older log never lands over a newer one.
    private var lastWrite: Task<Void, Never>?

    /// Loads the file once. Anything wrong with it gives an empty log; the next append replaces it.
    public init(url: URL = CommandLogStore.defaultURL) {
        self.url = url
        do {
            log = CommandLog.decode(try ConfigFile.readPrivateFile(at: url))
        } catch {
            PipelineLog.warning("command log: could not read the log file, starting empty", detail: "\(error)")
            log = CommandLog()
        }
    }

    /// Adds the entry and writes the file from a background task; the caller never waits for the write.
    public func append(_ entry: CommandLogEntry) {
        guard isRecording else { return }
        log.append(entry)
        onChange?()
        let data: Data
        do { data = try log.encoded() } catch {
            PipelineLog.warning("command log: could not encode the log", detail: "\(error)")
            return
        }
        let url = self.url, previous = lastWrite
        lastWrite = Task.detached {
            await previous?.value
            do { try ConfigFile.writePrivateFile(data, at: url) } catch {
                PipelineLog.warning("command log: could not write the log file", detail: "\(error)")
            }
        }
    }

    /// Empties the log at once and deletes the file after any write already queued, so old entries never reappear.
    public func clear() {
        log = CommandLog()
        onChange?()
        let url = self.url, previous = lastWrite
        lastWrite = Task.detached {
            await previous?.value
            do { try FileManager.default.removeItem(at: url) } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Already gone: nothing to clear.
            } catch {
                PipelineLog.warning("command log: could not delete the log file", detail: "\(error)")
            }
        }
    }
}
