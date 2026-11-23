# NH-157: Remove the never-written droppedJobs from VoicePipeline

**Date:** 2026-11-23
**Status:** Shipped
**Ticket:** [NH-157](https://github.com/noahstotland/nohands/issues/157)
**Shipped:** in PR #180, as specified

## Goal

`VoicePipeline.droppedJobs` (`Sources/NoHandsMac/VoicePipeline.swift`) is read and cleared but never appended to, so the code around it does nothing. Delete it.

## History

`git log -S droppedJobs`:

- NH-3 (f4c5666, PR #23) added it: on a stop phrase, `busy(_:)` moved the held job into `droppedJobs`, and `stop()` and the end of the task loop reported it as "dropped".
- NH-118 (ada1315, PR #123) changed `busy(_:)` to report the held job right away as stopped (`overlay.report(held.id, …, status: .stopped(PipelineText.dropped))` plus the `dropped` log line) and removed the append. The readers were left behind.

So the only writer was replaced on purpose by direct reporting. Nothing needs the list.

## Design

In `Sources/NoHandsMac/VoicePipeline.swift`:

- Delete `private var droppedJobs: [Job] = []` and its doc comment.
- `stop()`: `for job in [heldJob].compactMap({ $0 }) + droppedJobs { reportDropped(job, log: false) }` becomes `if let heldJob { reportDropped(heldJob, log: false) }`; delete `droppedJobs = []`.
- End of the task loop: `let lost = [heldJob].compactMap { $0 } + droppedJobs` becomes `let lost = heldJob`; delete `droppedJobs = []`; `if !stopped { for job in lost { reportDropped(job) } }` becomes `if let lost, !stopped { reportDropped(lost) }`.

Behavior is unchanged: a held job dropped by a stop phrase is still reported once, in `busy(_:)`, and a job still held when the task ends or the pipeline stops is still reported once at those points.

## Tests

None added. No behavior changes, and `VoicePipeline` is macOS integration code with no unit tests of its own (`AGENTS.md` § Testing). `swift build` and `swift test` must pass.

## Leaves out

- Any change to how held jobs replay (out of scope per the ticket).
- Any change to how a stop phrase reports the held job (NH-118's direct report stays).

## Calls I made

- **Delete, don't restore.** NH-118 replaced the append with a direct report so the corner panel shows the held job as stopped at once; restoring the list would report it twice.
- **No new test.** It is a dead-code removal in `NoHandsMac`; a test could not fail for a real bug here.
