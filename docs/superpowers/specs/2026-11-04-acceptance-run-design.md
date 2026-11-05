# NH-5: End-to-end acceptance run on real hardware — Design

**Date:** 2026-11-04  **Status:** Draft
**Ticket:** [NH-5](https://github.com/noahstotland/nohands/issues/5)

## Intent

Run the eight manual steps in the [design spec § 14](2026-11-04-nohands-design.md#14-acceptance-manual-end-to-end), record pass or fail and the latency per step, and replace the README's "not yet verified" status line with what is true.

The steps need a microphone, a person speaking and real apps. An agent can't do any of them, so the work splits in two, and the build stage never records a step as passed unless the user ran it and said so.

## What the build stage does itself

1. Build: `swift build`, `swift test`, then `scripts/bundle.sh`. Check that `build/NoHands.app` exists and `codesign -v build/NoHands.app` passes. No plan: the ticket changes only markdown.
2. Record the machine: `sysctl -n hw.model`, `sw_vers -productVersion`, chip from `sysctl -n machdep.cpu.brand_string`, and the commit SHA the bundle was built from.
3. Write `docs/superpowers/as-built/<run date>-acceptance-run.md` with the header lines from `docs/superpowers/README.md` (`**Shipped:** in PR #N`, `**Ticket:**`, `**Spec:**`), the machine block, and an empty results table:

   | # | Step (§ 14) | Result | asr ms (median / max) | total ms (median / max) | Notes |
   |---|---|---|---|---|---|
   | 1 | Launch, grant permissions, menu shows `CMD` | not run | n/a | n/a | |
   | 2–8 | one row per step | not run | | | |

   Latency columns are filled for steps 2–6 (grammar path, budget 650 ms total). Step 7 records its total but is not held to 650 ms. Step 8 passes when every grammar-path `total` from steps 2–6 is under 650 ms.
4. Draft the README status line for each outcome (all pass; some fail) so only the facts need filling in.
5. Stop with `BLOCKED:` and the reply template below. Do not open the PR yet.

## What only the user can do

Run steps 1–8 in order with Claude as the backend, on the bundle from step 1 above, then reply (relayed by the Chief of Staff) with:

```
Machine: <same as recorded? yes / no + model>
1: pass|fail <note>
...
8: pass|fail <note>
Latency (paste the output of):
log show --predicate 'subsystem == "dev.nohands.app"' --info --last 30m | grep 'total='
```

Transcripts are logged private, so the pasted lines show `<private>` in place of words; only the `[asr=… total=…]` part is needed.

## After the results arrive

- Fill the table from the reply only. A step the user did not report stays `not run`; the README line then names it as unverified.
- Compute median and max per step from the pasted lines, grouped by the order the user spoke them. If the lines can't be matched to steps, record overall grammar-path median and max and say so in Notes.
- Small fixes the run finds (one obvious change, no new behavior) go in this PR, with a test when the fix is in `NoHandsCore`. Anything bigger becomes a ticket via `write-ticket`, linked from the note's Notes column.
- README: replace the status line with one line, e.g. "Verified end to end on a MacBook Pro M3, macOS 15.1 (grammar-path median 310 ms)." or "Verified on … except steps 4 and 7 (see as-built)."
- Spec closeout per `docs/superpowers/README.md`, open the PR, run phases 3 and 4.

## Calls I made

- The build stage stops once, before the PR, and asks for all eight results in one reply rather than step by step.
- The run record lives in `as-built/` as the ticket says, even though nothing differs from a spec; the merge gate accepts the added as-built file.
- "Under 650 ms" for step 8 is judged per utterance (every grammar-path total), not on the median. Medians and maxes are recorded for information.
- The agent reads the machine details itself and asks the user only to confirm the run was on the same Mac.
- Step 7's latency is recorded but has no budget; the spec sets none for the model path.
- No new code, tests or scripts unless the run finds a small bug.

## Out of scope

- Automating any § 14 step.
- Re-running the intent fixtures against Claude (needs the network and a key; covered by other tickets).
- Latency tuning; a slow result becomes a ticket.
