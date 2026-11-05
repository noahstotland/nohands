import Foundation
import NoHandsCore

/// Runs agent-desktop commands; `AgentDesktopClient` conforms and tests script it.
public protocol DesktopCommandRunning: Sendable {
    func run(_ argv: [String], deadline: Duration?, isObservation: Bool, environment: [String: String]) async -> DesktopEnvelope
}

/// Spawns the `agent-desktop` binary once per command and decodes its one-line JSON envelope.
/// Never blocks the caller's actor: the child runs on a detached task, is killed at the deadline, and is killed
/// when the calling task is cancelled.
public struct AgentDesktopClient: DesktopCommandRunning, Sendable {
    public let binary: URL
    public let defaultDeadline: Duration

    public init(binary: URL, defaultDeadline: Duration) {
        self.binary = binary
        self.defaultDeadline = defaultDeadline
    }

    public func run(_ argv: [String], deadline: Duration? = nil, isObservation: Bool,
                    environment: [String: String] = [:]) async -> DesktopEnvelope {
        let command = argv.first { !$0.hasPrefix("-") } ?? ""
        let limit = deadline ?? defaultDeadline
        let child = Child()
        return await withTaskCancellationHandler {
            await Task.detached {
                child.launch(binary: binary, argv: argv, environment: environment, deadline: limit,
                             command: command, isObservation: isObservation)
            }.value
        } onCancel: {
            child.cancel()
        }
    }

    /// The child process and its outcome, guarded by a lock so the deadline timer, the cancellation handler and
    /// the launcher may all touch it.
    private final class Child: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var ended: String?   // "TIMEOUT" | "CANCELLED" once the child was killed on purpose

        func cancel() { kill(reason: "CANCELLED") }

        private func kill(reason: String) {
            lock.withLock {
                if ended == nil { ended = reason }
                process?.terminate()
            }
        }

        func launch(binary: URL, argv: [String], environment: [String: String], deadline: Duration,
                    command: String, isObservation: Bool) -> DesktopEnvelope {
            let p = Process()
            p.executableURL = binary
            p.arguments = argv
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            p.environment = env
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            let cancelledEarly: Bool = lock.withLock {
                process = p
                return ended != nil
            }
            if cancelledEarly { return .cancelled(command: command, isObservation: isObservation) }
            do { try p.run() } catch {
                return .processFailure(command: command, message: "could not run agent-desktop: \(error.localizedDescription)",
                                       observation: isObservation)
            }
            let timer = DispatchWorkItem { [weak self] in self?.kill(reason: "TIMEOUT") }
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(deadline / .milliseconds(1))), execute: timer)
            // Drain stdout on its own thread (a child that fills the pipe must not deadlock), but wait for the
            // child's exit, not for EOF: a helper grandchild that inherited the pipe would hold EOF open.
            let reader = Reader(handle: out.fileHandleForReading)
            p.waitUntilExit()
            timer.cancel()
            let data = reader.finish(grace: .milliseconds(300))
            let reason = lock.withLock { ended }
            if let reason {
                return reason == "TIMEOUT" ? .timeout(command: command, observation: isObservation)
                                           : .cancelled(command: command, isObservation: isObservation)
            }
            if let envelope = DesktopEnvelope.decode(data) { return envelope }
            let text = String(decoding: data.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return .processFailure(command: command,
                                   message: "agent-desktop exited \(p.terminationStatus)" + (text.isEmpty ? "" : ": \(text)"),
                                   observation: isObservation)
        }
    }
}

/// Accumulates a pipe's output on a background thread; `finish` waits briefly for EOF, then closes the pipe so a
/// lingering grandchild cannot hold the result hostage.
private final class Reader: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
        DispatchQueue.global().async { [self] in
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lock.withLock { data.append(chunk) }
            }
            done.signal()
        }
    }

    func finish(grace: DispatchTimeInterval) -> Data {
        if done.wait(timeout: .now() + grace) == .timedOut {
            try? handle.close()   // unblocks the reader; whatever arrived before the child's exit is the answer
            _ = done.wait(timeout: .now() + .seconds(1))
        }
        return lock.withLock { data }
    }
}

extension DesktopEnvelope {
    /// A convenience with the argument label the client uses.
    static func cancelled(command: String, isObservation: Bool) -> DesktopEnvelope {
        cancelled(command: command, observation: isObservation)
    }
}
