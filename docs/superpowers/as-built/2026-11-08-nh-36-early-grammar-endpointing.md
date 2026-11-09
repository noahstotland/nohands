# As-built: Act on short grammar commands sooner

**Shipped:** in PR #87
**Ticket:** NH-36
**Spec:** [2026-11-08-nh-36-early-grammar-endpointing-design.md](../specs/2026-11-08-nh-36-early-grammar-endpointing-design.md)

## Differs from the spec

- **`endpoint-test` runs in real time, and its replay lives in `NoHandsMac`.** The spec said "paced by chunk index". The replay (`EndpointReplay`, public, used by the CLI) feeds each 4096-sample chunk when its audio has elapsed, so Parakeet and the VAD overlap as they do live. It drives the real `VoicePipeline.runASR`, `MergeBuffer.earlyTranscript` and `EarlyCloseLedger` rather than a copy of their rules, which is why it sits in `NoHandsMac` (those types are internal). A file takes about as long to replay as it lasts, plus a second and a half of trailing silence.
- **The "full text" column is a separate transcription of the whole utterance.** After an accepted early close the app never transcribes the full audio, so the replay transcribes it once more outside the loop as the reference for the action comparison.
- **Latency is reported two ways.** `ready` is the spec's clock for an accepted early close: audio time of the chunk that raised the early silence, minus the true end (20 ms windows, RMS above 0.005), plus the wall time of the early transcription. A file where early close did not fire, or was rejected, shows `fallback` and its `fullReady` on the same clock.
- **Batch second pass, as chosen in the spec.** At the short silence the loaded Parakeet batch model transcribes the audio so far. The streaming managers need a different model (Parakeet Unified or the EOU model), which the ticket rules out, so there was nothing in scope to measure against.

## Measured: `endpoint-test` on synthesized speech

Re-run on the final head (after the review fix that keeps the first voiced chunk at `speechStart`).

20 utterances per phrase with macOS `say`: five voices (Samantha, Daniel, Karen, Moira, Tessa) at 150, 180, 210 and 240 words per minute, converted to 16 kHz mono wav. Default config (`silenceMs` 1000, `earlySilenceMs` 350), Apple M1 Pro, Parakeet v2, model and VAD cached.

| Phrase | Early fired | Accepted early | Fell back to full window | p50, true end to early text (accepted) | Range | Acted-on early text with a different action than the full text |
|---|---|---|---|---|---|---|
| new tab | 20 | 14 | 6 | 521 ms | 413 to 685 ms | 0 |
| scroll down | 20 | 20 | 0 | 591 ms | 469 to 707 ms | 0 |
| click 12 | 20 | 20 | 0 | 593 ms | 431 to 712 ms | 0 |
| stop | 20 | 19 | 1 | 612 ms | 453 to 725 ms | 0 |

p50 is the upper median (the `endpoint-test` summary line). For comparison, the same files on the full path (speech end to full text ready) had a p50 of about 1.3 to 1.4 s for every phrase.

Counting the fall-backs at their full-path time, the p50 per phrase is 573 ms (new tab), 591 ms, 593 ms and 638 ms (stop).

The fall-backs are recognition errors, not rule rejections: Parakeet heard "new tab" from Daniel and Tessa as "new time", "new type", "new Chad" and "new chat" (the full pass missed all but one of those too), and "stop" from Daniel at 240 wpm as "so". One file heard "new time" early and "new tab" in full: the early text parsed to nothing, so it was rejected and the full pass ran. No rejected or accepted early text parsed to a different action than the full text.

Both gates hold on these numbers, with a narrow latency margin: the four p50s sit between 521 and 612 ms against the 650 ms bar.

## What the replay did not cover

- **A live microphone.** The audio is clean synthesized speech with exact silence after it. Room noise, breath and a Mac's own speaker output may move the VAD's probability differently from silence, and a real voice trails off rather than stopping. A human run is still owed and goes in the PR's `Not proven` list; its readings are the logged `total` and `sinceVoice`.
- **Executor time.** The numbers stop when the early text is ready. Time to run the action (key press, scroll, click) comes on top.
- **Real-room silence and pauses.** No file has a pause inside a command, so the known risk is untested: a pause of 350 ms or more inside a closed command acts on the first part ("click twenty … three" clicks 20). `earlySilenceMs` 0 turns it off.
- **Other voices and accents.** Five Apple voices, one of which (Tessa) the recognizer mishears often.
- **The phrases beyond the four.** Key chords, modes, numbered clicks and the rest of the closed grammar are covered by `MergeBuffer.earlyTranscript` unit tests, not by audio.
