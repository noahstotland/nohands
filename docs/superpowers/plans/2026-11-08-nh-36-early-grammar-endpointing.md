# NH-36: Early grammar endpointing — Plan

**Spec:** [2026-11-08-nh-36-early-grammar-endpointing-design.md](../specs/2026-11-08-nh-36-early-grammar-endpointing-design.md) (approved at 845e934). The spec is the source of truth; this plan only orders the work.

Test command: `swift test`. Typecheck: `swift build`. Tests follow `AGENTS.md` § Testing: table-driven, one per rule, test lines not above feature lines.

## Task 1: Core pieces (`Sources/NoHandsCore`, `Tests/NoHandsCoreTests`)

1. `AppConfig.earlySilenceMs` (default 350, `decodeIfPresent`, clamp 0...3000 in `load`, CodingKeys). Test: default, clamp, missing key.
2. `EarlySilenceDetector` (pure struct): voiced / silent-by-probability input per chunk, fires once per silent run at `max(1, round(earlySilenceMs/256))` chunks, between-thresholds zone neither starts nor clears a run, never fires when early chunk count is not below the full (`silenceMs`) chunk count or `earlySilenceMs` is 0. Table-driven test.
3. `VadEvent.earlySilence`. `UtteranceAssembler`: `push` takes a `voiced` flag (default keeps old callers compiling), segment ids bumped on every close including forced cut, `snapshot()` returns `(id, samples, voicedEnd)`, closed utterances carry the same. Existing assembler tests stay unchanged and green.
4. `EarlyCloseLedger` (pure struct): per-segment offset used by an early close; `audio(forEarly:)` and `audio(forFull:)` per spec (nil when no voiced chunk after the offset, nil early when audio after the offset exceeds 4 s). Table-driven test.
5. `LatencyTrace.voiceEnd` and `sinceVoice` in `summary`; `asr` and `total` unchanged.
6. Free-text predicate on parsed `[Action]` (exhaustive `switch`; true for typed text, app/site opens, searches, clicks on a spoken name; false for key chords, modes, numbered/cursor clicks, scroll, move). Table-driven test over real `CommandGrammar.parse` phrases.

Verify: `swift build && swift test`. Commit `feat(core): early silence detector, ledger and trace (NH-36)`.

## Task 2: Mac pipeline (`Sources/NoHandsMac`, `Tests/NoHandsMacTests`)

1. `VoiceActivity.process` also returns the voiced flag (`probability >= speechThreshold`) and `.earlySilence` from the detector when the VAD itself has no event. Keep FluidAudio types out of the public API.
2. `MergeBuffer.earlyTranscript(_:trace:) -> Bool` and `wantsEarlyPass` per spec: stop phrases always accepted via the `transcript` stop path; otherwise command mode, `pending == nil`, `isComplete`, not `isUnfinished`, no free text. Never test `holdDuration == .zero`. Table-driven test (see spec § Tests).
3. `VoicePipeline`: extract the ASR loop into an internal function taking the job stream, transcriber and merge buffer; early and full jobs on the one serial stream; queue newest 4; VAD task enqueues early jobs only when `await merge.wantsEarlyPass`; early pass failure or empty text is ignored without `speechAbandoned`; full job audio nil after trimming calls `speechAbandoned`; `voiceEnd` stamped on traces; an early job's `speechEnd` is its creation time. Unit tests with a fake transcriber per spec § Tests (early runs once and late dropped; non-parsing early not acted on; stop after early command halts; words after early close are their own utterance; noise with no voiced chunk produces nothing; early pass that throws leaves full pass intact).

`MergeBufferTests` and `VoicePipelineTests` pass with no expectation changes. Verify: `swift build && swift test`. Commit `feat(mac): close grammar commands early at 350 ms of silence (NH-36)`.

## Task 3: CLI, README, measurement, as-built

1. `nohands-cli endpoint-test <wav>…` per spec § Measuring (real `VoiceActivity`, assembler, ledger, Parakeet; paced by chunk index; prints early text, full text, whether early fired, ms from true speech end to early text ready).
2. README: `earlySilenceMs` in the Configuration example and a sentence in "Pausing mid-command"; `endpoint-test` in the CLI table.
3. Generate 20 utterances for each of "new tab", "scroll down", "click 12", "stop" with `say` (vary voice and rate) into the scratchpad, run `endpoint-test`, and compute p50 per phrase and early-vs-full action mismatches. Gates: p50 under 650 ms per phrase, and zero early texts that parse to a different action than the full text. If either misses, stop with `BLOCKED:` and the numbers; do not lower a bar or change what is measured.
4. Write `docs/superpowers/as-built/2026-11-08-nh-36-early-grammar-endpointing.md` with the choice of batch, the numbers, and what the replay did not cover (live microphone, executor time). Set the spec's Status/Shipped lines per the repo's as-built convention.

Verify: `swift build && swift test`, and the intent fixtures `.build/debug/nohands-cli eval scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json` still pass. Commit `feat(cli): endpoint-test and docs for early endpointing (NH-36)`.
