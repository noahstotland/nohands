import Foundation

/// How hard an accessibility walk looks. Browsers get a larger budget and the page first,
/// because a web page holds far more nodes than a native window.
public struct WalkPolicy: Equatable, Sendable {
    public var budget: Duration
    public var maxNodes: Int
    public var pageFirst: Bool

    public init(budget: Duration, maxNodes: Int, pageFirst: Bool) {
        self.budget = budget
        self.maxNodes = maxNodes
        self.pageFirst = pageFirst
    }

    public static let app = WalkPolicy(budget: .milliseconds(150), maxNodes: 2000, pageFirst: false)
    public static let browser = WalkPolicy(budget: .milliseconds(600), maxNodes: 5000, pageFirst: true)

    /// In a browser: the page first, with the larger of the caller's budget and `browser`'s (a caller that
    /// already walks for a second, like the task loop, keeps it). Elsewhere: the caller's own.
    public static func pick(isBrowser: Bool, default d: WalkPolicy) -> WalkPolicy {
        guard isBrowser else { return d }
        return WalkPolicy(budget: max(d.budget, browser.budget), maxNodes: max(d.maxNodes, browser.maxNodes), pageFirst: true)
    }
}
