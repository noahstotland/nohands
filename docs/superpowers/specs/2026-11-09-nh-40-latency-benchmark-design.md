# NH-40: A repeatable latency benchmark — Design

**Date:** 2026-11-09  **Ticket:** [NH-40](https://github.com/noahstotland/nohands/issues/40)
**Status:** Shipped
**Shipped:** in PR #102, with differences: [as-built](../as-built/2026-11-09-nh-40-latency-benchmark.md)

## Intent

`nohands-cli bench <dir>` replays a folder of recordings and prints a per-file table and p50 and p95 per stage, so latency work has before-and-after numbers.

`EndpointReplay` (NH-36) already replays audio through the real VAD, assembler, ASR loop and merge buffer. Short commands now close at about 350 ms, not `silenceMs`, so a VAD-transcriber-parser benchmark would report a roughly 1 s path the app no longer takes.

## Goals and limits

- Never report numbers for a path the app doesn't take.
- Dry run: no action, no network, stops at the parse (merge-window hold, model path and executor are not measured).
- No CI, thresholds or stored baselines; `endpoint-test` unchanged; `swift test` never needs audio or models.

## Approaches

- **Extend `EndpointReplay` and add `bench`** (chosen): the app's own path, with early close.
- A new unpaced loop: rejected (skips early close).

## How it works

- `EndpointReplay.Report` gains how the measured utterance closed (early or full), `speechEndLagMs` (audio time of the closing chunk minus the true end of speech), `asrMs`, the acted text and the utterance count. The measured pass is the accepted early pass, else the last closed utterance. Replay stays paced to real time (16 files, about a minute).
- `bench <dir>` reads `.wav` files directly in the directory, sorted. It blanks `attentionWord` (recordings lack it); the header says so and prints `silenceMs`.
- It loads Parakeet and runs two warm-up passes (the first two runs are cold). Load time counts in no stage.
- `end-to-end = speechEndLagMs + asrMs + parseMs`, parse being `CommandGrammar` on the acted text.
- Output: one row per file, then counts and p50 and p95 for lag, asr, parse and end-to-end.
- A missing directory or no `.wav` exits 1, pointing at `Tests/Fixtures/audio/README.md`. An unreadable file, no utterance or empty text is a `skipped:` row left out of the percentiles. Exit 1 only if nothing was measured.
- `LatencyStats` (Core) has nearest-rank `percentile` and `summaryLine`.
- `scripts/make-bench-audio.sh [outdir]` generates the 16-phrase set with `say` as 16 kHz mono WAV into git-ignored `.build/bench-audio/`. `Tests/Fixtures/audio/README.md` explains recording (one phrase per file, quiet room).
- The as-built holds the first run's numbers and says the audio is synthesized.

## Tests

One table-driven test for `percentile` and `summaryLine`. The replay and command need the models, so they are manual checks.

## Calls I made

1. **The baseline uses synthesized speech; your recordings are still owed.** An agent can't speak. `bench Tests/Fixtures/audio`, the ticket's acceptance command, exits asking for recordings until you add them, and goes in the PR's `Not proven` list.
2. **The `say` audio is generated, not committed:** I couldn't confirm Apple's licence allows redistributing it. Your own recordings may be committed.
3. **Early close is measured,** unlike the ticket's stage list; percentiles pool early and full closes.
4. **With 16 files, p95 is the slowest file.** Compare p50s.
5. **Lag uses NH-36's RMS "true end of speech"** (threshold 0.005), so numbers compare. Noise can make lag read low or negative; it is printed as is.
6. **The dictation sentence runs in command mode,** so it shows `no match -> LLM`.
