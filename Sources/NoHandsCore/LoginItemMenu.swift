import Foundation

/// Where the app's login item stands; the app maps `SMAppService.Status` onto it.
public enum LoginItemState: Equatable, Sendable {
    case enabled, notRegistered, requiresApproval, notFound
}

/// What the "Start at Login" menu item shows and does for each state.
public struct LoginItemMenuItem: Equatable, Sendable {
    public enum Checkmark: Equatable, Sendable { case on, off, mixed }
    public enum Action: Equatable, Sendable { case register, unregister, openSettings, none }

    public let title: String
    public let checkmark: Checkmark
    public let isEnabled: Bool
    public let action: Action
}

public enum LoginItemMenu {
    public static func item(for state: LoginItemState) -> LoginItemMenuItem {
        switch state {
        case .enabled:
            LoginItemMenuItem(title: "Start at Login", checkmark: .on, isEnabled: true, action: .unregister)
        case .notRegistered:
            LoginItemMenuItem(title: "Start at Login", checkmark: .off, isEnabled: true, action: .register)
        case .requiresApproval:
            // Registering again would loop: the user has to allow it under Login Items.
            LoginItemMenuItem(title: "Start at Login: allow in Login Items", checkmark: .mixed, isEnabled: true,
                              action: .openSettings)
        case .notFound:
            LoginItemMenuItem(title: "Start at Login: run the app from build/NoHands.app", checkmark: .off,
                              isEnabled: false, action: .none)
        }
    }
}
