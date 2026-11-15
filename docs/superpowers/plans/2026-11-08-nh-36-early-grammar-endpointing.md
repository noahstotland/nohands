# NH-36: Early grammar endpointing — Plan

**Spec:** [2026-11-08-nh-36-early-grammar-endpointing-design.md](../specs/2026-11-08-nh-36-early-grammar-endpointing-design.md) (approved at 845e934). The spec is the source of truth; this plan only orders the work.

Verify with `swift build && swift test`.

## Task 1: Core

- `AppConfig.earlySilenceMs` (default 350, clamp 0...3000).
- `EarlySilenceDetector`: fires once per silent run; never when the early count is not below the full `silenceMs` count.
- `UtteranceAssembler` voiced flag and segment ids; `EarlyCloseLedger` picks audio per pass.
- `LatencyTrace.voiceEnd`; a free-text predicate on actions.

## Task 2: Mac pipeline

- `MergeBuffer.wantsEarlyPass`: stop phrases always; otherwise command mode, nothing pending, complete, no free text.
- `VoicePipeline`: early and full jobs on one serial stream; a failed early pass is ignored.

## Task 3: CLI, README, measurement

- `nohands-cli endpoint-test <wav>…`, README.
- Gates over 20 `say` utterances per phrase: p50 under 650 ms and zero early texts parsing differently from the full text. On a miss, stop with `BLOCKED:`; do not lower a bar.
- Write the as-built note.
