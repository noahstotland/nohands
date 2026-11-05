# NH-5: Acceptance run on real hardware, as built

**Shipped:** in PR #N (filled in when the PR opens)
**Ticket:** [NH-5](https://github.com/noahstotland/nohands/issues/5)
**Spec:** [2026-11-04-acceptance-run-design.md](../specs/2026-11-04-acceptance-run-design.md)

Steps are from [design spec § 14](../specs/2026-11-04-nohands-design.md#14-acceptance-manual-end-to-end). Results are filled from what the user reported, never inferred. A step not reported stays `not run`.

## Machine

| Item | Value |
|---|---|
| Model | MacBookPro18,3 |
| Chip | Apple M1 Pro |
| macOS | 14.5 |
| Built from commit | ff91756f90dff6b02e2650fef3008186747dc525 |
| Build | `scripts/bundle.sh`, ad-hoc signature, `codesign -v` passes; `swift test` 355 tests pass |
| Backend | Claude |

## Results

| # | Step (§ 14) | Result | asr ms (median / max) | total ms (median / max) | Notes |
|---|---|---|---|---|---|
| 1 | Launch, grant permissions, menu shows `CMD` | not run | n/a | n/a | |
| 2 | Dictation into TextEdit | not run | | | |
| 3 | Stop dictating, copy, Safari, new tab, URL | not run | | | |
| 4 | Numbered labels, grid, zoom, click | not run | | | |
| 5 | Scroll, hold click, move, release (drag) | not run | | | |
| 6 | Sleep and wake | not run | | | |
| 7 | Model command: "make this window full screen" | not run | n/a | | No 650 ms budget on the model path |
| 8 | Every grammar-path total from steps 2 to 6 under 650 ms | not run | n/a | n/a | |

## README status line drafts

- All pass: "Verified end to end on a MacBook Pro (Apple M1 Pro), macOS 14.5 (grammar-path median <N> ms)."
- Some fail or not run: "Verified on a MacBook Pro (Apple M1 Pro), macOS 14.5, except steps <list> (see [as-built](docs/superpowers/as-built/2026-11-04-acceptance-run.md))."
