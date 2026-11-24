# NH-40 latency benchmark: plan

Spec: [design](../specs/2026-11-09-nh-40-latency-benchmark-design.md). Test: `swift test`. Typecheck: `swift build`.

## Task 1: `LatencyStats` (NoHandsCore) with its test

- `Sources/NoHandsCore/LatencyStats.swift`: `percentile(_:_:)` (nearest rank, nil when empty) and `summaryLine(stage:values:)` as the spec's [Summary format](../specs/2026-11-09-nh-40-latency-benchmark-design.md) says. Foundation only.
- `Tests/NoHandsCoreTests/LatencyStatsTests.swift`: one table covering empty, one value, unsorted input, sub-10 ms two decimals, whole-ms rounding. Run with `swift test --filter LatencyStatsTests`.

## Task 2: Replay fields (NoHandsMac)

- `EndpointReplay.Report` gains `closedBy`, `speechEndLagMs`, `asrMs`, `actedText`, `utterances`, defined as in the spec. Existing fields and `endpoint-test` output do not change.
- Record the measured pass: the accepted early pass, else the pipeline's transcription of the last closed utterance (from the `Recorder` log). The reference re-transcription is not measured.

## Task 3: `bench <dir>` (nohands-cli)

- New `bench` case in `Sources/nohands-cli/main.swift` and `usage()`, per the spec's Command section: `.wav` files in sorted order, config with `attentionWord` blanked, Parakeet load plus two warm-up passes, per-file rows, `skipped:` rows, summary and `LatencyStats` lines, exit codes. Time `CommandGrammar(config: config.grammarConfig).parse` for `parseMs`.
- Executes nothing and builds no resolver.
- `nohands-cli bench /nonexistent` and an empty directory exit 1 with the message.

## Task 4: Audio, docs

- `scripts/make-bench-audio.sh [outdir]`: 16 phrases with `say` (pinned voice and rate), 16 kHz 16-bit mono WAV, default `.build/bench-audio/`. The pause phrase is two `say` outputs joined by 600 ms of silence.
- `Tests/Fixtures/audio/README.md`: phrases and recording notes. No audio checked in.
- `README.md` CLI table row for `bench <dir>`.

## Task 5: Run and as-built

- Run `scripts/make-bench-audio.sh`, then `.build/debug/nohands-cli bench .build/bench-audio`.
- Write `docs/superpowers/as-built/2026-11-09-nh-40-latency-benchmark.md` per `docs/superpowers/README.md`: the first run's table and summary, Mac model, macOS version, config, and that the audio is synthesized. Add differences from the spec.
- If the run cannot finish (models missing, no `say` voice), stop with `BLOCKED:` and the output.
