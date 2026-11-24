import Foundation
import Testing
@testable import NoHandsCore
@testable import NoHandsMac

/// What the menu and Browse say about the configured registry, and that nothing is offered to fetch when it can't be trusted.
@Test func theConfiguredRegistryIsReadyOnlyWithAnHTTPSURLAndAKey() {
    let key = Data(repeating: 7, count: 32).base64EncodedString()
    let table: [(url: String?, key: String?, menu: String?, reason: String?)] = [
        (nil, nil, "Registry: none set", "No pack registry yet, set packRegistryURL in config.json"),
        ("", nil, "Registry: off", "The pack registry is off (packRegistryURL is empty)"),
        ("http://packs.example.org/i.json", key, "Registry URL must be https", "Registry URL must be https"),
        ("https://packs.example.org/i.json", nil, "Registry: no key", "Registry has no key, set packRegistryKey in config.json"),
        ("https://packs.example.org/i.json", "not base64", "Registry: no key", "Registry has no key, set packRegistryKey in config.json"),
        ("https://packs.example.org/i.json", key, nil, nil),
    ]
    for row in table {
        var config = AppConfig()
        config.packRegistryURL = row.url
        config.packRegistryKey = row.key
        switch RegistryStatus(config: config) {
        case .ready(let url, let keys): #expect(row.menu == nil && url.host == "packs.example.org" && keys.count == 1, "\(row)")
        case .unavailable(let menu, let reason): #expect(menu == row.menu && reason == row.reason, "\(row)")
        }
    }
}
