import Foundation

public enum ScreenshotKind: String, Equatable, Codable, Sendable {
    /// The whole screen, saved where macOS saves screenshots.
    case screen
    /// The crosshair: the speaker drags it out.
    case selection
    /// The camera pointer: the speaker clicks the window to take.
    case window
}

/// A System Settings pane the speaker can name. `rawValue` is the macOS 14 extension id.
public enum SettingsPane: String, Equatable, Codable, Sendable, CaseIterable {
    case wifi = "com.apple.wifi-settings-extension"
    case bluetooth = "com.apple.BluetoothSettings"
    case sound = "com.apple.Sound-Settings.extension"
    case displays = "com.apple.Displays-Settings.extension"
    case accessibility = "com.apple.Accessibility-Settings.extension"
    case privacy = "com.apple.settings.PrivacySecurity.extension"
    case loginItems = "com.apple.LoginItems-Settings.extension"
    case notifications = "com.apple.Notifications-Settings.extension"
    case battery = "com.apple.Battery-Settings.extension"
    case general = "com.apple.systempreferences.GeneralSettings"

    /// The address System Settings opens at this pane. Built here from the fixed table, never from speech.
    public var url: URL { URL(string: "x-apple.systempreferences:" + rawValue)! }

    private static let spoken: [String: SettingsPane] = [
        "wifi": .wifi, "wi-fi": .wifi, "wi fi": .wifi, "bluetooth": .bluetooth,
        "sound": .sound, "audio": .sound, "display": .displays, "displays": .displays,
        "accessibility": .accessibility,
        "privacy": .privacy, "privacy and security": .privacy, "security": .privacy,
        "login items": .loginItems, "startup items": .loginItems,
        "notifications": .notifications, "battery": .battery, "general": .general,
    ]

    /// The pane the words name (already normalized); nil for an unknown or empty name, never a guess.
    public static func parse(_ words: [String]) -> SettingsPane? { spoken[words.joined(separator: " ")] }
}

/// A system chore by voice ("lock screen", "screenshot", "next space", "open bluetooth settings", "empty trash").
/// Grammar only; the model has no kind for it.
public enum SystemCommand: Equatable, Codable, Sendable {
    case lockScreen
    case screenshot(ScreenshotKind)
    case missionControl
    case showDesktop
    /// Switch Space; the grammar only makes `.left` and `.right`.
    case space(Direction)
    case notificationCenter
    case openSettings(SettingsPane)
    case emptyTrash
}

/// What "empty trash" needs from Finder's "Show warning before emptying the Trash" setting. With it off, Finder erases
/// without asking, and nothing else asks for a fixed phrase, so the command refuses.
public enum EmptyTrash {
    public static let warningOff = "Finder's Trash warning is off: turn it on in Finder Settings > Advanced, or empty the Trash by hand"
    public static let alreadyEmpty = "the Trash is already empty"

    /// `warnOnEmptyTrash` is Finder's `WarnOnEmptyTrash` value, nil when unset (the default, on). The failure line, or nil to go on.
    public static func refusal(warnOnEmptyTrash: Bool?) -> String? { warnOnEmptyTrash == false ? warningOff : nil }
}
