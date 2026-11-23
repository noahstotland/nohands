# NH-153: Reliable timing tests: Plan

Spec: `docs/superpowers/specs/2026-11-23-nh-153-reliable-timing-tests-design.md`. Test files only.

1. `TaskRunnerTests`: `rig()` and the hand-built runners in `settleWaitsForTwoEqualObservations` and `settleStopsAtMax` take `now: { clock.now() }` from a frozen `FakeClock`.
2. `MergeBufferTests`: add `waitForOutput` (polls every 10 ms, at most 5 s) and use it where a test waits for a release; widen the unfinished window in `attentionWordAloneWaitsForTheRestOfTheCommand`.
3. `ActionExecutorTests.aSpokenStopDuringTheTabReadKeepsTheTabUnpressed`: the fake read signals it started and blocks until the test has cancelled.
4. `AgentDesktopClientTests`: wider deadline in `runReportsProcessFailureAndMalformedOutput`; longer grandchild, deadline and bound in the grandchild test.
5. Verify: 10 parallel `swift test` runs, count timing failures (PackDraftTests excluded, see spec).
