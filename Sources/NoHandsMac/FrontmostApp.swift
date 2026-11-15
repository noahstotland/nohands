import Foundation
import AppKit
import os

/// The bundle ID of the frontmost app, kept current on app activation, for code that cannot touch the main actor
/// (the merge buffer's closing checks). One per process; it watches activations for the life of the app.
final class FrontmostApp: Sendable {
    static let shared = FrontmostApp()

    private let id = OSAllocatedUnfairLock<String?>(initialState: nil)

    var bundleID: String? { id.withLock { $0 } }

    private init() {
        // The first read can come before any activation: start from the current frontmost app (a lazy static is
        // first touched on the main actor, where the pipeline is built).
        let current = MainActor.assumeIsolated { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
        id.withLock { $0 = current }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.id.withLock { $0 = app?.bundleIdentifier }
        }
    }
}
