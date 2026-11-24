# NH-36: Act on short grammar commands sooner — Design

**Date:** 2026-11-08  **Ticket:** [NH-36](https://github.com/noahstotland/nohands/issues/36)
**Status:** Shipped
**Shipped:** in PR #87, with differences: [as-built](../as-built/2026-11-08-nh-36-early-grammar-endpointing.md)

## Intent

"New tab" waits a full second of silence (`silenceMs` 1000 ms, so people can pause mid-command), about 1.3 s from the end of speech. Close the utterance at about 350 ms of silence only when the words so far are a complete grammar command or a stop phrase. Everything else keeps today's window.

Non-goals: a new ASR model; model-path latency (#37, #38).

Anti-goals (a failure even if the numbers pass): a "stop" lost, delayed or merged; words after an early command dropped; a mid-way pause reaching the model as two requests; any change to dictation; any network call.

## Approach

Chosen: at the short silence, run a second batch Parakeet pass on the audio so far (one extra pass per pause, command mode only). Rejected: FluidAudio streaming managers (other models, ruled out) and a 350 ms `silenceMs` (splits mid-command pauses).

## How it works

- **`EarlySilenceDetector`** (Core, pure) reads the probability `VoiceActivity` already gets. A probability at or above `speechThreshold` clears the silence run; below the negative threshold (else `speechThreshold - 0.15`) it starts one. It fires once per run at `max(1, round(earlySilenceMs / 256))` chunks. A real `speechStart` or `speechEnd` wins over the new `.earlySilence` event.
- **Off** when `earlySilenceMs` is 0 or not below `silenceMs` in chunks.
- **`UtteranceAssembler`** takes a per-chunk voiced flag (the VAD's verdict, not RMS: up to 750 ms of breath or action noise can follow an early close and must not reach Parakeet). On `.earlySilence` the caller takes a `snapshot()`. Each segment has an id, bumped at every close.
- **`EarlyCloseLedger`** (Core, pure) records the offset an early close used. The early job gets the audio after it, or is skipped when no voiced chunk follows or the audio is over 4 s. The full job is trimmed the same way.
- **After an early close the rest of the segment is kept** as the next utterance; no voiced chunk after it means no late transcript.
- **ASR loop** (`VoicePipeline`): `.early` and `.full` jobs share the one serial stream, so an early pass finishes before the full pass of its segment. Queue grows from newest 2 to 4. Early jobs only in command mode. An early pass that throws or returns empty is ignored.
- **`MergeBuffer.earlyTranscript`** (on the actor, check and emit atomic):
  - A stop phrase is always accepted in command mode, even with words pending.
  - Otherwise accept only if: command mode, `pending == nil`, `isComplete`, not `UtteranceMerger.isUnfinished` after the attention word, and no spoken free text in the actions.
  - Call `isComplete` and `isUnfinished` directly, never `holdDuration == .zero` (zero for unparsed text when `mergeWindowMs` is 0).
  - `pending == nil` keeps "click the ... go back" whole.
- **Free-text commands keep the full window** (`type`, `open`, `go to`, `search for`, `click <name>`): "type hello ... world" would type half. A Core predicate over parsed actions marks them. Key chords, modes, numbered clicks, scroll and move may close early.

## Config

`AppConfig.earlySilenceMs: Int = 350` (clamped 0...3000; 0 is off). Documented in the README.

## Measuring

The logged `total` starts after the silence wait, so a build with no early close could pass.

- `LatencyTrace` gains `voiceEnd` (last voiced chunk) and a `sinceVoice` summary field. `asr` and `total` are unchanged.
- New CLI `endpoint-test <wav>...` replays files through the real pipeline and prints early text, full text, whether early fired, and time from true speech end to early text.
- 20 `say` utterances per phrase. Two gates:
  1. p50 per phrase under 650 ms from true speech end to early text.
  2. No early text parses to a different action than the full text.
- A missed gate stops the build with `BLOCKED:`. No bar is lowered.

## Tests

Table-driven, no microphone or model: detector, assembler, ledger, config, the `earlyTranscript` accept/reject table, and the ASR loop with a fake transcriber (early command runs once, stop after it halts, words after it run alone).

## Calls I made

1. **Words after an early close are kept, not discarded.** Literal discard would swallow "stop" in "new tab ... stop" and lose the second "next tab".
2. **Free-text commands don't close early,** against the ticket: likeliest to be mid-phrase.
3. **The latency bar starts when the voice stops,** not at the logged `total`.
4. **Numbers come from synthesized speech; a live mic test is still owed** (PR).
5. **Added the accuracy gate.**
6. **Dictation and sleep get no early pass, stop included:** a dictated "stop ... the car" would change the text.
7. **An early close needs an empty merge buffer** (stop aside).
8. **No revoke if speech resumes during the early pass** (about 200 ms); the words run alone.
9. **Known risk:** a 350 ms pause inside a command that already parses acts on the first part ("click twenty ... three" clicks 20). Set `earlySilenceMs` 0 to avoid it.
10. **350 ms rounds to one 256 ms chunk.**
