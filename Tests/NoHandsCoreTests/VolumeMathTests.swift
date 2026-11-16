import Testing
@testable import NoHandsCore

@Test func volumeChangesClampToZeroAndOneHundred() {
    let table: [(VolumeChange, Int, Int?)] = [
        (.set(40), 90, 40), (.set(150), 10, 100), (.set(-5), 10, 0),
        (.by(10), 95, 100), (.by(-30), 20, 0), (.by(-10), 50, 40), (.by(5), 0, 5),
        (.mute(true), 50, nil), (.mute(false), 50, nil),
    ]
    for (change, current, expected) in table { #expect(VolumeMath.apply(change, current: current) == expected) }
}
