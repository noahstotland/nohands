import Foundation
import NoHandsCore

/// Builds a `ScreenObservation` of the frontmost app. Only collects; titles/URLs are untrusted and
/// are sanitized by the request builder.
public struct ScreenObserver: Sendable {
    private let ax: any ElementProviding
    private let maxElements: Int

    public init(ax: any ElementProviding, maxElements: Int) {
        self.ax = ax
        self.maxElements = maxElements
    }

    /// `labels` holds exactly the elements listed in the observation (titled, first `maxElements` by number).
    /// While number badges are shown (`overlay` is `.labels`), the badges' own elements and numbers are used, so a
    /// number the model picks is the one the user sees. Safe to call off the main actor (`ax` is thread-safe).
    public func observe(mode: Mode, overlay: OverlayState) -> (observation: ScreenObservation, labels: [Int: UIElementInfo]) {
        let all: [Int: UIElementInfo]
        if case .labels(let badges) = overlay { all = badges } else { all = LabelAssigner.assign(ax.actionableElements()) }
        var listed: [ObservedElement] = []
        var snapshot: [Int: UIElementInfo] = [:]
        for n in all.keys.sorted() {
            guard let e = all[n], !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if listed.count >= maxElements { break }
            var role = e.role
            if role.hasPrefix("AX") { role.removeFirst(2) }
            listed.append(ObservedElement(number: n, role: role.lowercased(), title: e.title))
            snapshot[n] = e
        }
        let observation = ScreenObservation(
            app: ax.frontmostAppName() ?? "", windowTitle: ax.focusedWindowTitle() ?? "",
            url: ax.webURL(), mode: mode, overlay: overlay.kindName, elements: listed)
        return (observation, snapshot)
    }

    /// True once right after an observation first exposed a Chromium page tree: observe again before trusting it.
    public func didJustExpose() -> Bool { ax.didJustExpose() }
}
