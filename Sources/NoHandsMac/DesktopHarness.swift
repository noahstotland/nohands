import Foundation
import NoHandsCore

/// What a harness action did, folded from agent-desktop's `disposition`.
public enum HarnessActionResult: Equatable, Sendable {
    case delivered(verified: Bool)
    /// Nothing reached the app: safe to fall back or retry. The message is for the HUD.
    case notDelivered(String)
    /// The action may have landed; final.
    case failed(String)
    /// The ref no longer matches the screen (STALE_REF, AMBIGUOUS_TARGET, SNAPSHOT_NOT_FOUND, ELEMENT_NOT_FOUND).
    case elementChanged
}

/// The task loop's observation and action backend (agent-desktop today; the native path is the absence of one).
public protocol DesktopHarness: AnyObject, Sendable {
    var kind: HarnessKind { get }
    /// Elements of `app`'s focused window (several windows → the focused or first visible one), or of `surface`.
    /// nil when agent-desktop cannot read it: the caller falls back to the native walk.
    func snapshot(app: String, surface: DesktopSurface?, timeoutMs: Int) async -> DesktopSnapshot?
    /// Exact name first, then a contains match.
    func find(app: String?, surface: DesktopSurface?, name: String) async -> DesktopFindMatch?
    /// Runs an action; retries once with `--headed` when nothing was delivered and the harness allows it; keeps
    /// the result's open surfaces for `takeOpenSurfaces()`.
    func act(_ command: DesktopCommand) async -> HarnessActionResult
    /// `get`, `clipboard-get`, `list-notifications` → their text; nil on error.
    func read(_ command: DesktopCommand) async -> String?
    func listWindows(app: String) async -> [DesktopWindowCandidate]
    /// Surfaces (sheet, menu, …) the last action left open; reading clears them.
    func takeOpenSurfaces() -> [String]
    func startSession(name: String) async -> String?
    func endSession(_ id: String) async
}
