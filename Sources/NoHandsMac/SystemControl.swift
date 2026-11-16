import Foundation
import AppKit
import ApplicationServices

/// What the system voice commands need beyond key presses. `MacSystemControl` is the real one; tests use a fake.
public protocol SystemControlling: Sendable {
    /// Opens Mission Control, or shows the desktop (`showDesktop`: Mission Control's own argument), whatever the user
    /// has bound the shortcuts to. False when the app would not open.
    func openMissionControl(showDesktop: Bool) async -> Bool
    /// Whether the screenshot tool's own process (`screencaptureui`, the crosshair and window camera) is running.
    func isScreenCaptureUIRunning() -> Bool
    /// Presses the menu-bar clock, which opens Notification Center on macOS 14. False when no clock is found.
    func pressMenuBarClock() -> Bool
    /// Finder's "Show warning before emptying the Trash"; nil when the key is unset (the default, on).
    func finderWarnsOnEmptyTrash() -> Bool?
}

public struct MacSystemControl: SystemControlling {
    public init() {}

    private static let missionControl = URL(fileURLWithPath: "/System/Applications/Mission Control.app")
    private static let clockID = "com.apple.menuextra.clock"
    /// The apps whose menu bar extras hold the clock: Control Center on macOS 14, SystemUIServer on older systems.
    private static let extraHosts = ["com.apple.controlcenter", "com.apple.systemuiserver"]

    public func openMissionControl(showDesktop: Bool) async -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        if showDesktop { config.arguments = ["1"] }
        do {
            _ = try await NSWorkspace.shared.openApplication(at: Self.missionControl, configuration: config)
            return true
        } catch {
            return false
        }
    }

    public func isScreenCaptureUIRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui").isEmpty
    }

    public func pressMenuBarClock() -> Bool {
        for id in Self.extraHosts {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                let host = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(host, 0.3)
                guard let bar = AXQuery.element(host, "AXExtrasMenuBar") else { continue }
                for item in AXQuery.elements(bar, kAXChildrenAttribute)
                where AXQuery.string(item, "AXIdentifier") == Self.clockID {
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    public func finderWarnsOnEmptyTrash() -> Bool? {
        CFPreferencesCopyAppValue("WarnOnEmptyTrash" as CFString, "com.apple.finder" as CFString) as? Bool
    }
}
