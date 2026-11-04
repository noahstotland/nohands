import Foundation

/// Retry schedule for rebuilding the audio engine after a configuration change.
public struct RestartBackoff: Sendable, Equatable {
    public var maxRetries: Int
    public var interval: TimeInterval
    public init(maxRetries: Int = 3, interval: TimeInterval = 0.5) {
        self.maxRetries = maxRetries
        self.interval = interval
    }

    /// Delay before the next attempt after `failures` consecutive failures; nil when retries are exhausted.
    public func delay(afterFailures failures: Int) -> TimeInterval? {
        failures >= 1 && failures <= maxRetries ? interval : nil
    }
}
