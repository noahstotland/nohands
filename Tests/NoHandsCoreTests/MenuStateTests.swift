import Testing
@testable import NoHandsCore

@Test func staleJobPolicy() {
    #expect(!StaleJobPolicy.isStale(age: .seconds(8)))
    #expect(StaleJobPolicy.isStale(age: .milliseconds(8001)))
    #expect(!StaleJobPolicy.isStale(age: .seconds(1)))
    #expect(StaleJobPolicy.isStale(age: .seconds(3), maxAge: .seconds(2)))
}

@Test func configFileSecurity() {
    #expect(!ConfigFileSecurity.isTooOpen(posixPermissions: 0o600))
    #expect(ConfigFileSecurity.isTooOpen(posixPermissions: 0o644))
    #expect(ConfigFileSecurity.isTooOpen(posixPermissions: 0o640))
    #expect(ConfigFileSecurity.isTooOpen(posixPermissions: 0o602))
}

@Test func menuStateResolution() {
    func r(mic: Bool = false, ax: Bool = true, err: String? = nil, ready: Bool = true, paused: Bool = false) -> MenuState {
        MenuState.resolve(micDenied: mic, accessibilityGranted: ax, error: err, pipelineReady: ready, paused: paused)
    }
    #expect(r() == .listening)
    #expect(r(paused: true) == .paused)
    #expect(r(ready: false) == .loading)
    #expect(r(ax: false, paused: true) == .needsAccessibility)
    #expect(r(mic: true, ax: false) == .microphoneDenied)
    #expect(r(err: "boom") == .error("boom"))
    #expect(MenuState.error("x").text == "Error: x")
    #expect(MenuState.error("x").showsRetry)
    #expect(!MenuState.listening.showsRetry)
    #expect(MenuState.title(mode: .sleep, paused: false) == "ZZZ")
    #expect(MenuState.title(mode: .dictation, paused: true) == "⏸ DICT")
}
