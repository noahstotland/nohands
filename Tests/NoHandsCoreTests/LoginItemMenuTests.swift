import Testing
@testable import NoHandsCore

@Test func loginItemMenuPerState() {
    typealias Item = LoginItemMenuItem
    let rows: [(LoginItemState, Item)] = [
        (.enabled, Item(title: "Start at Login", checkmark: .on, isEnabled: true, action: .unregister)),
        (.notRegistered, Item(title: "Start at Login", checkmark: .off, isEnabled: true, action: .register)),
        // Stuck approval opens Settings; calling register() again would loop.
        (.requiresApproval, Item(title: "Start at Login: allow in Login Items", checkmark: .mixed, isEnabled: true,
                                 action: .openSettings)),
        (.notFound, Item(title: "Start at Login: run the app from build/NoHands.app", checkmark: .off, isEnabled: false,
                         action: .none)),
    ]
    for (state, expected) in rows {
        #expect(LoginItemMenu.item(for: state) == expected, "\(state)")
    }
}
