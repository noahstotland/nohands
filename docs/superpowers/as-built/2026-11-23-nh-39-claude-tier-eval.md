# As-built: NH-39 Claude model tiers on the intent fixtures

**Shipped:** in PR #187
**Ticket:** NH-39
**Spec:** [2026-11-05-nh-39-measure-claude-model-tiers-design.md](../specs/2026-11-05-nh-39-measure-claude-model-tiers-design.md)

## Decision

**No default changes, and there is no fast tier.** No (model, effort) pair passes every case on either file, so
nothing qualifies to replace the current default under the spec's 100% rule. `claude-haiku-5-5` at `low` (set
by NH-95, for cost, before this measurement) stays. The fast-tier idea (`intentFastModel`) is dropped: Haiku at
`low` is already the fastest pair measured, so there is no faster tier to put in front of it.

What the numbers say, for the user's call (not acted on here):

- Haiku at `low` trails the others by 4 to 19 points: 81% and 73% against 88% to 92% for Opus and 85% to 92%
  for Sonnet. Haiku at `medium` is no better on the main file (80%) and 12 points better on the disfluent file (85%).
- Its p50 is 43% to 45% lower than Opus (1078 ms against 1895 to 1943 ms on the main file). Haiku at `low` also has the lowest p95 on both files.
- Sonnet at `low` is 0 to 2 points under Opus at `low` and 6% to 18% faster at p50. It is the middle option if
  Haiku's accuracy matters more than its price.
- Effort made no consistent difference (`low` vs `medium` within 2 points on Sonnet and Opus). Where it did
  (Haiku, disfluent file, +12 points) the sample is 42 calls.

## Method

- `nohands-cli eval <file> --runs 3 --model <id> --effort <level>` for each of 6 pairs on both fixture files:
  `scripts/intent-eval.json` (45 cases, 135 calls per pair) and `scripts/intent-eval-disfluent.json` (14 cases,
  42 calls per pair). 1,062 calls, plus a 14-call check run before them. Pairs ran back to back, one call at a time.
- Run on 2026-11-23 on a MacBook Pro (arm64, 16 GB), one network, a debug build of `cef5e4a` (this branch with
  `origin/main` merged in). Defaults for everything else: `llmDeadlineMs` 12000, so a timeout
  would count as a fail (none showed in the logs; every FAIL line carried a model answer).
- A call passes when `IntentEval.matches(actions, status:, anyOf:)` accepts it (the actions, and the step `status`
  only for the one fixture case that sets one).
- Latency is wall time per call, including HTTP; p50 and p95 are nearest-rank over every call (no warm-up
  dropped for Claude).

## Results

`scripts/intent-eval.json` (135 calls per pair)

| Model | Effort | Pass | p50 | p95 |
|---|---|---|---|---|
| claude-haiku-5-5 | low | 110/135 (81%) | 1078 ms | 2019 ms |
| claude-haiku-5-5 | medium | 108/135 (80%) | 1250 ms | 2830 ms |
| claude-sonnet-5-5 | low | 117/135 (86%) | 1599 ms | 2104 ms |
| claude-sonnet-5-5 | medium | 115/135 (85%) | 1583 ms | 2190 ms |
| claude-opus-5-5 | low | 120/135 (88%) | 1943 ms | 3062 ms |
| claude-opus-5-5 | medium | 119/135 (88%) | 1895 ms | 3279 ms |

`scripts/intent-eval-disfluent.json` (42 calls per pair)

| Model | Effort | Pass | p50 | p95 |
|---|---|---|---|---|
| claude-haiku-5-5 | low | 31/42 (73%) | 1235 ms | 2086 ms |
| claude-haiku-5-5 | medium | 36/42 (85%) | 1274 ms | 3033 ms |
| claude-sonnet-5-5 | low | 39/42 (92%) | 1720 ms | 2188 ms |
| claude-sonnet-5-5 | medium | 38/42 (90%) | 1684 ms | 2192 ms |
| claude-opus-5-5 | low | 39/42 (92%) | 1835 ms | 2523 ms |
| claude-opus-5-5 | medium | 39/42 (92%) | 1853 ms | 2554 ms |

## Failing cases

Counts are failed calls out of 18 per case (3 runs × 6 pairs).

| Case (`say`) | Failed in | Pairs that missed it |
|---|---|---|
| go to the the downloads folder (disfluent) | 18 | 6 of 6 |
| take me into the downloads folder | 18 | 6 of 6 |
| copy this then paste it below | 18 | 6 of 6 |
| jot down that the meeting moved to friday | 15 | 6 of 6 |
| make safari full screen | 15 | 5 of 6 |
| choose the second tab | 10 | 5 of 6 |
| launch safari and visit wikipedia | 7 | 3 of 6 |
| scroll way down | 7 | 3 of 6 |
| the other 12 cases | 1 to 6 each | 1 to 2 of 6, mostly Haiku |

Six cases fail on at least 5 of 6 pairs, Opus at `medium` included. The wrong answers differ from the
fixture's expected action: the downloads phrases get `openFile` (or an empty list) where the fixture clicks
label 3, "choose the second tab" gets ⌘2 where it clicks label 2, "make safari full screen" gets
`moveWindow(.maximize)` where it presses ⌃⌘F, "copy this then paste it below" adds an extra key to the expected
sequence, and "jot down …" opens Notes on Opus and Sonnet where the fixture types into Mail (Haiku types the
right text with a trailing period, which the matcher does not normalise). These point at the prompt or the
fixture, not the tier. Both are out of scope here (no prompt or fixture
edits). Opus at `medium`, the pre-NH-95 default, itself passes 88% and 92%, so "both files stay at 100% on the
chosen default" cannot be met by any pair today.

## Cost of a two-model option (not built)

Had a fast tier qualified, each model would keep its own prompt cache of the same system prompt. The main
model's cache would be warmed only by task steps 2 and later and by re-asks, so it would go cold more often,
and a request handed up from the fast tier would pay the fast call's latency plus a main-tier call that may miss
the cache. Today (before #37) there is no cache to lose, only the extra call.

## Differs from the spec

- **No `intentFastModel`/`intentFastEffort` keys, no `IntentTier`, no resolver change.** Dropped for the reason
  under Decision. The spec's step 5 and its tests were not built.
- **Defaults were already Haiku at `low`** (NH-95 merged after the spec was written), so the spec's baseline
  "opus/medium" is now one row of the table, not the running default.
- **Numbers went to `docs/configuration.md`, `docs/tasks.md` and `docs/cli.md`**, not "README § Configuration":
  the README no longer holds those sections. The note is dated 2026-11-23, not 2026-11-05.
- **1,062 calls, not 972**, because the main fixture file grew from 40 to 45 cases after the spec.

## Follow-up proposed

- A ticket to look at the six shared failures (the folder, second-tab, full-screen, copy/paste and jot-down
  phrases): fix the prompt or the fixture, then rerun this table.
- A product call on whether Haiku at `low`'s 4 to 19 point gap is worth its price saving; Sonnet at `low` is the
  nearest alternative.

## Checks that ran

- `swift build` clean; `swift test` passes except `PackDraftTests.testKeptAndLeftOut`, which already fails on `main`.
- The 12 eval runs above (logs kept outside the repo).
