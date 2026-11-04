import Testing
@testable import NoHandsCore

@Test func restartBackoffRetriesThreeTimesThenGivesUp() {
    let b = RestartBackoff()
    #expect(b.delay(afterFailures: 1) == 0.5)
    #expect(b.delay(afterFailures: 2) == 0.5)
    #expect(b.delay(afterFailures: 3) == 0.5)
    #expect(b.delay(afterFailures: 4) == nil)
    #expect(b.delay(afterFailures: 0) == nil)
}
