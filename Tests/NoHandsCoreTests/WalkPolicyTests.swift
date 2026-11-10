import Testing
@testable import NoHandsCore

@Test func browserWalkOnlyInBrowsers() {
    let big = WalkPolicy(budget: .seconds(1), maxNodes: 6000, pageFirst: false)
    let table: [(Bool, WalkPolicy, WalkPolicy)] = [
        (true, .app, .browser), (false, .app, .app), (false, big, big), (true, big, WalkPolicy(budget: .seconds(1), maxNodes: 6000, pageFirst: true)),
    ]
    for (isBrowser, d, expected) in table {
        #expect(WalkPolicy.pick(isBrowser: isBrowser, default: d) == expected)
    }
}
