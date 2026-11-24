import Foundation
import NoHandsCore
import os

/// The session's running Claude token total. One per process (`shared`), so it survives the resolver being rebuilt
/// when the config or backend changes, and it sees the calls of tasks that were later cancelled. Counts only.
public final class ClaudeUsageMeter: Sendable {
    public static let shared = ClaudeUsageMeter()

    private let state = OSAllocatedUnfairLock(initialState: ClaudeUsageTotal())

    public init() {}

    /// Counts one call that got a 2xx response; a nil usage (no `usage` object) still counts as a call.
    public func record(_ usage: ClaudeUsage?) {
        state.withLock { $0 = $0.adding(usage) }
    }

    public var total: ClaudeUsageTotal { state.withLock { $0 } }
}
