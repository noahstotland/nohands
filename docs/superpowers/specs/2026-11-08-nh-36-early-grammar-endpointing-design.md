# NH-36: Act on short grammar commands sooner — Design

**Date:** 2026-11-08  **Ticket:** [NH-36](https://github.com/noahstotland/nohands/issues/36)
**Status:** Draft

## Intent

"New tab" waits a full second of silence before anything happens, so a command the grammar already understands takes
about 1.3 s from the end of speech. `silenceMs` went up to 1000 ms so people can pause mid-command, and that reason
still holds for anything that doesn't parse. A phrase that is already a complete command doesn't need the wait.

Close the utterance early, at about 350 ms of silence, only when the words heard so far are a complete grammar command
or a stop phrase. Everything else keeps today's window.

## Goals and non-goals

Goals are the ticket's Scope and Acceptance, with the measurement changes in [Measuring](#measuring).

Non-goals are the ticket's Out of scope: changing the ASR model or FluidAudio version, and the model path's latency
(#37, #38).

Anti-goals, which would make this a failure even if the numbers pass:

- A spoken "stop" is lost, delayed past today's path, or merged into something else.
- Words spoken after an early command are silently thrown away.
- A phrase that pauses mid-way reaches the model as two requests.
- Dictation changes in any way.
- Any new network call. All of this is on-device.

## Approaches

1. **Second batch pass on the audio so far (chosen).** At the short silence, snapshot the audio, run the existing
   Parakeet batch transcriber on it, and test the text. It uses the loaded model, adds no dependency, and the build
   measures its latency. It costs one extra ASR pass per pause in command mode, off the main actor.
2. **FluidAudio streaming manager.** Ruled out without a measurement. `StreamingUnifiedAsrManager` loads a different
   model (Parakeet Unified) with a stated 2.08 s theoretical latency, and `StreamingEouAsrManager` needs the EOU
   model. Neither is in the local model cache. Adopting one is the "changing the ASR model" the ticket puts out of
   scope.
3. **Just lower `silenceMs` to 350 ms.** The original setting, already rejected: every mid-command pause splits the
   request.

## How it works

```
mic chunk -> VoiceActivity -> UtteranceAssembler
                 | speechEnd        -> full job  (today's path)
                 | earlySilence     -> early job (command mode only)
                                            |
                 serial ASR loop: early and full jobs, in order, through EarlyCloseLedger
                                            |
                 MergeBuffer.earlyTranscript  (accepts or ignores)
                 MergeBuffer.transcript       (today's path)
```

### Detecting the short silence (`VoiceActivity`, Core detector)

New pure struct `EarlySilenceDetector` in `NoHandsCore`. It reads the `probability` that `VadStreamResult` already
returns, so there is no second Silero inference. It mirrors FluidAudio's streaming rule:

- `probability >= speechThreshold` clears the silence run.
- `probability < negativeThreshold` while in speech starts a run. Values between the two thresholds neither start nor
  clear one.
- It fires once per run, when the run reaches `max(1, round(earlySilenceMs / 256))` chunks.

The effective negative threshold is the one FluidAudio uses: the configured one, else `speechThreshold - 0.15`.

`VadEvent` gains `.earlySilence`. `VoiceActivity.process` returns the VAD's own event when there is one, so a real
`speechStart` or `speechEnd` always wins, and `.earlySilence` otherwise. It also returns whether the chunk was voiced
(`probability >= speechThreshold`), which the assembler records.

Early close is off when `earlySilenceMs` is 0, or when its chunk count is not below the chunk count of `silenceMs`.
Then the detector never fires and the app behaves exactly as today.

### Cutting the audio (`UtteranceAssembler`)

`push` keeps its behaviour for every existing event, and takes the chunk's voiced flag. On `.earlySilence` it returns
nothing and the caller asks for a new `snapshot()`.

Each utterance segment gets an id, bumped at every close including a forced max-length cut. A snapshot and a closed
utterance both carry `(id, samples, voiced end)`, where `samples` is everything since the segment began and voiced end
is the index after the last voiced chunk. The existing RMS check for `minSpeechMs` stays as it is.

### Which jobs get transcribed (`EarlyCloseLedger`, Core)

New pure struct used only by the serial ASR loop. It records, per segment, the offset of the audio an early close has
already used, and it answers two questions:

- **`audio(forEarly:)`**: the samples after that offset, or nil to skip the pass. Skip when no voiced chunk lies after
  the offset, or when the audio after it is longer than 4 s (no grammar command is that long, and long speech must not
  pay for repeated passes).
- **`audio(forFull:)`**: the same trimming. With no early close it returns the samples whole. After an early close it
  returns only what came after, or nil when no voiced chunk follows.

"Voiced" means the VAD's verdict, not RMS. Between an early close and `speechEnd` there can be up to 750 ms of breath,
room noise or sound from the action that just ran. If RMS decided, that audio would go to Parakeet and could become a
phantom request to the model.

**After an early close, the rest of the segment is not thrown away.** Audio after the offset is treated as the next
utterance. If no voiced chunk follows, the late transcript never exists, which is what the ticket asks for. If the
user keeps talking, those words are transcribed on their own. See the first entry in [Calls I made](#calls-i-made).

### The ASR loop (`VoicePipeline`)

Move the body of today's `asrTask` into an internal function that takes the job stream, the transcriber and the merge
buffer, so a fake transcriber can drive it in tests.

- Jobs are `.early(segment)` and `.full(segment)` on the one existing serial stream, so an early pass always finishes
  before the full pass of the same segment.
- The queue grows from newest 2 to newest 4, so early jobs can't push a full utterance out of the old capacity.
- The VAD task enqueues an early job only when `await merge.wantsEarlyPass` is true, which means mode is command. In
  dictation and sleep no early job exists.
- An early pass that throws or returns empty text is ignored without calling `speechAbandoned`, because the utterance
  is still open. The full pass runs as today.
- If a full job's audio is nil after trimming, call `speechAbandoned` and move on.

### Accepting early text (`MergeBuffer`)

New `earlyTranscript(_:trace:) -> Bool`, on the actor so the check and the emit are atomic:

- A stop phrase is always accepted, in command mode, even with words pending. It goes through the existing `transcript`
  stop path, so it discards pending words exactly as today and is never merged.
- Otherwise accept only when all of these hold: mode is command, `pending == nil`, `isComplete(text, mode)` is true,
  `UtteranceMerger.isUnfinished` is false for the phrase after the attention word, and the parsed actions carry no
  spoken free text.
- An accepted text goes through `transcript`, so there is one path to `emit`.

The rule must call `isComplete` and `isUnfinished` directly and must **not** test `holdDuration == .zero`. With
`mergeWindowMs` set to 0, `hold` returns zero for text that doesn't parse, and half a sentence would go to the model
at 350 ms.

Requiring `pending == nil` keeps a mid-way pause whole: "click the … go back" still merges, because "click the" is
pending when "go back" is heard.

**Free-text commands keep the full window.** `isComplete` accepts `type <words>`, `open <name>`, `go to <x>`,
`search for <x>` and `click <name>`, and any of them can still be mid-phrase at 350 ms: "type hello … world" would type
half and send the rest to the model, the failure the `spell` exclusion exists to prevent. "open youtube … and search
for cats" is one model request today and would split. A new Core predicate on the parsed actions, written as an
exhaustive `switch` so a new action must choose, returns true for typed text, app and site opens, searches and clicks
on a spoken name. It returns false for key chords, modes, numbered clicks, cursor clicks, scroll and move.

The attention word needs no special case: `isComplete` already requires it.

## Config

`AppConfig.earlySilenceMs: Int = 350`, decoded with `decodeIfPresent`, clamped to 0...3000 in `load`. 0 turns early
close off. README § Configuration gets the key in the example and a sentence on the two-stage behaviour in "Pausing
mid-command".

## Measuring

**The ticket's bar, `total`, can't prove this feature on its own.** `LatencyTrace.speechEnd` is stamped when the VAD
reports the end, which is after the silence wait. Today's `total` already leaves out the 1 s the ticket is about, so a
build with no early close could pass it.

- `LatencyTrace` gains `voiceEnd`: when the last voiced chunk arrived. `summary` adds `sinceVoice=…ms`, from `voiceEnd`
  to `actionsDone` (or `asrDone` if actions have not finished). `asr` and `total` keep their meaning so old logs stay
  comparable: `speechEnd` for an early job is the moment that job was created. `voiceEnd` is at chunk granularity and
  can understate by up to 256 ms. This field is what the live run on the microphone reads.
- New CLI subcommand `endpoint-test <wav>…` (README CLI table). It replays each file through the real `VoiceActivity`,
  assembler, ledger and Parakeet, paced by chunk index, and prints the early text, the full text, whether early fired,
  and the time from true speech end (the `vad-test` 20 ms RMS method) to early text ready.
- The build generates 20 utterances each of the four phrases with `say`, varying voice and rate.
- **Two gates decide the build, both on the `endpoint-test` numbers.** The true-end clock is the stricter one because
  it can't understate. It leaves out the executor, which only the live run covers.
  1. Latency: p50 per phrase, true speech end to early text ready, under 650 ms.
  2. Accuracy: of the utterances where early fired, none whose early text parses to a different action than the full
     text. A wrong command that can't be corrected is worse than a slow one.
- If either gate misses, the build reports the numbers and stops with `BLOCKED:`. It does not lower a bar or change what
  is measured.
- The as-built note reports these numbers and the logged `total` and `sinceVoice` from any live run.

## Tests

One table-driven test per rule, per `AGENTS.md` § Testing:

- `EarlySilenceDetector`: fires once per run at the chunk count, a voiced chunk resets it, the between-thresholds zone
  neither starts nor clears a run, off when early is not below full.
- `UtteranceAssembler`: snapshot carries the id and offsets, and ids bump on close and forced cut.
- `EarlyCloseLedger`: trimming, the 4 s skip, and nil when no voiced chunk follows an early close.
- `AppConfig`: default, clamp, missing key.
- `MergeBuffer.earlyTranscript`: accept and reject table covering complete, numbered click, free text (`type`, `open`,
  `go to`, `click <name>`), dangling, `spell`, pending words, stop with pending words, dictation, sleep, attention word
  on, and `mergeWindowMs` 0 with unparsed text.
- ASR loop with a fake transcriber: early text that parses runs once and the late transcript is dropped; early text
  that doesn't parse is not acted on and the full text runs; a stop said after an early command still halts; words
  after an early command run as their own utterance; noise with no voiced chunk after an early close produces nothing; an early pass that throws leaves the full pass intact.

`MergeBufferTests` and `VoicePipelineTests` stay green with no expectation changes. No test needs the microphone or a
model.

## Left to the builder

- Exact type and method names beyond those above.
- Whether the segment type lives beside `UtteranceAssembler` or in its own file.
- How `say` output is varied, as long as the numbers are reported.

## Calls I made

1. **Words after an early close are kept, not discarded.** The ticket says "discard the rest of that utterance". Done
   literally, "new tab … stop" with a pause under 1 s would swallow the stop, breaking a repo invariant, and "next tab
   … next tab" would lose the second command. Silence after an early close produces no second transcript, which is
   what the ticket's test describes.
2. **Free-text commands don't close early** (`type`, `open`, `go to`, `search for`, `click <name>`). The ticket's rule
   would include them. They are the commands most likely to be mid-phrase at 350 ms, and "open youtube … and search
   for cats" would split. So only closed commands get faster: keys, modes, numbered clicks, scroll, move, stop.
3. **The latency bar starts when the voice stops, not at the logged `total`.** The logged `total` starts after the
   silence wait, so it passes today.
4. **The numbers come from replaying synthesized speech, and a live test is still owed.** An agent can't speak into the
   microphone. The ticket's 20-per-phrase bar is met with `say` audio through the real VAD and Parakeet, per phrase. A
   human run on the mic goes in the PR's `Not proven` list. Synthesized audio has cleaner silence than a room.
5. **Added a second gate the ticket doesn't have:** no early text in the replay may parse to a different action than
   the full text.
6. **Batch, not streaming, chosen without a streaming measurement.** The streaming managers need a different model,
   which the ticket rules out, so there was nothing in scope to measure.
7. **Dictation and sleep get no early pass at all, stop phrases included.** The ticket says stop phrases close early
   and also says dictation is unchanged. A dictated "stop … the car" would otherwise change the typed text. A stop in
   dictation arrives on today's path, as it does now.
8. **An early close needs an empty merge buffer**, stop phrases aside. This is stricter than the ticket, and it keeps
   the mid-way pause guarantee.
9. **A result is not revoked if speech resumes during the early ASR pass** (about 200 ms). The resumed words become
   their own utterance. A cancel path would add a back channel from the VAD to the ASR loop for a very small window.
10. **Known remaining risk.** A pause of 350 ms or more inside a closed command that already parses acts on the first
    part: "go back … to the home page", or "click twenty … three" clicks 20. Anyone who pauses that way can set
    `earlySilenceMs` to 0. This is the trade the ticket asks for.
11. **Early passes stop above 4 s of audio**, and the ASR queue grows from 2 to 4 jobs.
12. **`earlySilenceMs` is a chunk count underneath.** 350 ms rounds to one 256 ms VAD chunk, the same rounding the
    file's comment already documents.
