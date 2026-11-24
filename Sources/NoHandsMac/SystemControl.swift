import Foundation
import AppKit
import ApplicationServices
import NoHandsCore
import os

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
    /// The Automation permission for System Events, read without asking: the raw status code (0 granted, -1743 denied,
    /// -1744 never asked, -600 System Events is not running). Never shows a prompt.
    func automationStatus() -> Int
    /// Starts asking for the permission on a detached thread (macOS shows its prompt) and returns at once. One request
    /// at a time; a second call while the prompt is up does nothing.
    func requestAutomation()
    /// Starts System Events hidden and waits up to 2 s for it. False when it did not come up.
    func startSystemEvents() async -> Bool
    /// Runs the one fixed script with the appearance's raw value as its argument.
    func runAppearance(_ appearance: Appearance) async -> ChildResult
    /// Runs the shortcut by `name` (one of the two fixed names), 5 s at most.
    func runShortcut(_ name: String) async -> ChildResult
    /// The output of `shortcuts list`, nil when it could not run.
    func listShortcuts() async -> String?
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

    /// The only AppleScript NoHands sends, compiled into the app. Nothing spoken, modelled or configured reaches it; its
    /// one argument is `Appearance.rawValue`.
    static let appearanceScript = """
        on run argv
            tell application "System Events" to tell appearance preferences
                if item 1 of argv is "toggle" then
                    set dark mode to not dark mode
                else
                    set dark mode to (item 1 of argv is "dark")
                end if
                return dark mode
            end tell
        end run
        """
    private static let systemEvents = URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app")
    private static let deadline: Duration = .seconds(5)
    private static let asking = OSAllocatedUnfairLock(initialState: false)

    public func automationStatus() -> Int { Self.determinePermission(ask: false) }

    public func requestAutomation() {
        guard Self.asking.withLock({ asking in
            if asking { return false }
            asking = true
            return true
        }) else { return }
        // The call blocks until the user answers the prompt, so it never runs on the pipeline's thread.
        Thread.detachNewThread {
            _ = Self.determinePermission(ask: true)
            Self.asking.withLock { $0 = false }
        }
    }

    private static func determinePermission(ask: Bool) -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: AutomationAccess.systemEventsID)
        guard let desc = target.aeDesc else { return -1 }
        return Int(AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, ask))
    }

    public func startSystemEvents() async -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        config.hides = true
        _ = try? await NSWorkspace.shared.openApplication(at: Self.systemEvents, configuration: config)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while NSRunningApplication.runningApplications(withBundleIdentifier: AutomationAccess.systemEventsID).isEmpty {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    public func runAppearance(_ appearance: Appearance) async -> ChildResult {
        await ChildProcess.run("/usr/bin/osascript", ["-e", Self.appearanceScript, appearance.rawValue], deadline: Self.deadline)
    }

    public func runShortcut(_ name: String) async -> ChildResult {
        await ChildProcess.run("/usr/bin/shortcuts", ["run", name], deadline: Self.deadline)
    }

    public func listShortcuts() async -> String? {
        guard case .exited(0, let output) = await ChildProcess.run("/usr/bin/shortcuts", ["list"], deadline: Self.deadline) else { return nil }
        return output
    }

    public func finderWarnsOnEmptyTrash() -> Bool? {
        CFPreferencesCopyAppValue("WarnOnEmptyTrash" as CFString, "com.apple.finder" as CFString) as? Bool
    }
}
