import Foundation
import ServiceManagement
import NoHandsCore

/// The app's own login item (`SMAppService.mainApp`). The state is read from the system every time, never cached.
@MainActor
public enum LoginItem {
    public static var state: LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .notRegistered: .notRegistered
        case .requiresApproval: .requiresApproval
        // `.notFound` means "no app bundle" for `swift run`. Inside a bundle it only means nothing is registered
        // yet (some macOS versions report it before the first register), so the item must stay clickable.
        case .notFound: Bundle.main.bundleURL.pathExtension == "app" ? .notRegistered : .notFound
        @unknown default: .notRegistered
        }
    }

    public static func register() throws { try SMAppService.mainApp.register() }

    public static func unregister() throws { try SMAppService.mainApp.unregister() }

    /// Opens System Settings > General > Login Items.
    public static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
