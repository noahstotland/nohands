import Foundation
import NoHandsCore
import os

/// Runs a child by absolute path with an argument array: no shell, stdin closed, stdout and stderr together, killed at
/// the deadline. Blocks a GCD thread, never the caller's actor or the cooperative pool.
enum ChildProcess {
    static func run(_ path: String, _ arguments: [String], deadline: Duration) async -> ChildResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<ChildResult, Never>) in
            DispatchQueue.global().async {
                continuation.resume(returning: runBlocking(path, arguments, deadline: deadline))
            }
        }
    }

    private static func runBlocking(_ path: String, _ arguments: [String], deadline: Duration) -> ChildResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        // Drained while the child runs, so output past the pipe's buffer cannot stall it.
        let collected = OSAllocatedUnfairLock(initialState: Data())
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty { collected.withLock { $0.append(chunk) } }
        }
        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return .couldNotStart
        }
        let seconds = Double(deadline.components.seconds)
        let timedOut = exited.wait(timeout: .now() + seconds) == .timedOut
        if timedOut {
            // The output is thrown away, so nothing drains after this: a child that outlives SIGTERM is killed, and
            // waiting for end of output could hold the pipeline (and `stop`) behind it.
            process.terminate()
            if exited.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            pipe.fileHandleForReading.readabilityHandler = nil
            return .timedOut
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        if let rest = try? pipe.fileHandleForReading.readToEnd() { collected.withLock { $0.append(rest) } }
        let text = String(decoding: collected.withLock { $0 }, as: UTF8.self)
        return .exited(Int(process.terminationStatus), text)
    }
}
