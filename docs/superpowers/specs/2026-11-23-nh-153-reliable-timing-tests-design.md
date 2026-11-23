# NH-153: Make the timing tests reliable in a parallel swift test run: Design

**Date:** 2026-11-23  **Ticket:** [NH-153](https://github.com/noahstotland/nohands/issues/153)
**Status:** Draft

## Intent

A full parallel `swift test` fails one or two timing tests per run on a loaded machine. Remove the dependence on wall-clock speed so a parallel run is reliable, without weakening what each test checks.

Non-goals: new tests; serial-only test configuration; changes to app behaviour.

Anti-goals: a test that can no longer fail when its timeout, poll count or cancellation breaks.

## Reproduced on main

Five parallel `swift test` runs on `origin/main` (e42f9a9), on the developer's Mac:

| Run | Timing failures |
|---|---|
| 1 | none |
| 2 | `nonGrammarPhraseWaitsForTheWindow`, `settleStopsAtMax`, `aTickingValueStopsTheSettleAtTheSecondPoll` |
| 3 | `abandonedSpeechResumesTheWindow`, `settleStopsAtMax` |
| 4 | none |
| 5 | none |

Every run also failed `PackDraftTests.testKeptAndLeftOut` (`.menuItem(..., exact: true)` where the test expects `exact: false`). It fails the same way every time, so it is not a timing problem and is out of scope here (see Calls I made).

## What each test waits on, and the fix

### TaskRunner settle (`TaskRunnerTests`): an injected clock

`TaskRunner.settle` counts the injected sleeps plus the **measured wall time** of each observation (`now()`), and stops at `settleMs`. `rig()` and the two hand-built runners in `settleWaitsForTwoEqualObservations` and `settleStopsAtMax` use the real clock, so under load a fake AX walk "takes" tens of milliseconds, eats the settle budget and the poll count comes out short (`settleStopsAtMax` saw 3, not 4; `aTickingValueStopsTheSettleAtTheSecondPoll` saw fewer than 2).

Fix: these runners get `now: { clock.now() }` with a frozen `FakeClock` (the same as `harnessRig` already does). Elapsed time is then the injected sleeps only, which is what the expected counts assume. Covered: `settleStopsAtMax`, `settleWaitsForTwoEqualObservations`, `aTickingValueStopsTheSettleAtTheSecondPoll`, `settleWaitDependsOnWhatTheStepDid` and every other `rig()` test. `settleObservesOffTheMainActorAndCountsWalkTime` already uses a fake clock that advances per walk and stays as is.

Still fails for a real bug: if settle ignores `settleMs` it polls past 4 (or never stops); if the ticking-value rule breaks it polls to the 3000 ms limit (12 sleeps, not 2).

### MergeBuffer windows (`MergeBufferTests`): wait for the signal

The buffer releases held text from a `Task.sleep` timer (80 ms window, 200 ms unfinished window). The tests sleep a fixed 200–250 ms and then expect the text; on a loaded machine the timer task wakes later than that.

Fix: a small test helper `released(_ sink:, equals:)` polls every 10 ms until the sink holds the expected text, for at most 5 s, and returns whether it did. Every check that waits for a release uses it: `nonGrammarPhraseWaitsForTheWindow`, `speechResumingInsideTheWindowMergesBothHalves`, `abandonedSpeechResumesTheWindow`, `addressedSpellWaitsOutThePauseBetweenLetters`.

Still fails for a real bug: 5 s is well under the buffer's 20 s safety timeout, so a buffer that stops resuming the window after abandoned speech (and only flushes on the safety timeout) still fails `abandonedSpeechResumesTheWindow`; one that never releases fails every one.

The checks that something is **not** released yet (`#expect(sink.out.isEmpty)` after a short sleep inside a window) keep their fixed sleeps. A slow wake can only make them fail if the test oversleeps the whole window; `attentionWordAloneWaitsForTheRestOfTheCommand` sleeps 150 ms inside a 400 ms window, so its unfinished window widens to 5000 ms (the next transcript releases at once, so the test is no slower). The others are checks that text never fires (reset, stop), which a slow wake cannot break.

### Tab read and stop (`ActionExecutorTests.aSpokenStopDuringTheTabReadKeepsTheTabUnpressed`): a signal

The fake tab read sleeps 200 ms on its thread; the test cancels after a 50 ms sleep. If the test wakes after the read has finished, the tab is pressed and the test fails.

Fix: the fake read blocks on a semaphore. The test waits (off the main actor, at most 5 s) until the read has started, cancels, then releases the read. The cancel always lands mid-read, which is the case the test is about.

Still fails for a real bug: if `goToTab` stops checking cancellation after the read, the tab is pressed.

### agent-desktop child processes (`AgentDesktopClientTests`): wider bounds

These run real shell scripts, so there is no clock to inject.

- `runReportsProcessFailureAndMalformedOutput`: a 1 s deadline for `echo nope; exit 1`. A slow spawn hits the deadline and reports `TIMEOUT`. The deadline widens to 10 s; the test is about the failure code, not the deadline.
- `runReturnsWhenTheChildExitsEvenIfAGrandchildHoldsStdout`: the grandchild holds stdout for 3 s and the test wants a return in under 1.5 s. The grandchild now sleeps 20 s, the deadline is 10 s, and the bound is under 8 s. A client that waits for stdout to close hits the deadline instead and fails `e.ok`, so the test still catches it with more headroom.

`runKillsAtDeadline` and `runIsCancellable` (a 5 s child, a bound under 2 s) have not failed and keep their bounds.

## Acceptance

- `swift test` (parallel) shows no timing failures in 10 runs in a row on the developer's Mac. The PR lists each run.
- The PR names, for each changed test, the case above that still fails when its behaviour breaks.

## Calls I made

- `PackDraftTests.testKeptAndLeftOut` fails deterministically on main, most likely since NH-150 (#173) made pack menu steps exact. It is not a timing test, so this PR leaves it alone and the 10-run acceptance counts timing failures only. It needs its own ticket (which side is right, the test or `exact: true`, is a product call).
- The ticket lists `aSpokenStopDuringTheTabReadKeepsTheTabUnpressed` under `TaskRunnerTests`; it lives in `ActionExecutorTests` and is the only ActionExecutor test with a short race. "The settle tests in ActionExecutorTests" use `exposureSettle: .zero` or a 5 s wait and need no change.
- MergeBuffer gets no injected sleep: polling for the released text is enough and keeps the app code untouched. Only test files change.
- Tests that have not failed and have a wide margin keep their bounds, so the diff stays small.
