# As-built: Act on short grammar commands sooner

**Shipped:** in PR #87
**Ticket:** NH-36
**Spec:** [2026-11-08-nh-36-early-grammar-endpointing-design.md](../specs/2026-11-08-nh-36-early-grammar-endpointing-design.md)

## Differs from the spec

- **`endpoint-test` runs in real time, and its replay lives in `NoHandsMac`.** The spec said "paced by chunk index". The replay feeds each 4096-sample chunk when its audio has elapsed and drives the real `VoicePipeline.runASR`, `MergeBuffer.earlyTranscript` and `EarlyCloseLedger` (internal types, hence `NoHandsMac`).
- **The "full text" column is a separate transcription,** the reference for the action comparison (an accepted early close never transcribes the full audio).
- **Latency is reported two ways.** `ready` is the early close's audio time minus the true end (20 ms windows, RMS above 0.005), plus the early transcription's wall time. A file where early close did not fire or was rejected shows `fallback` and its `fullReady`.

## Measured

Synthesized speech (`say`, five voices, 150 to 240 wpm), defaults (`silenceMs` 1000, `earlySilenceMs` 350), M1 Pro, Parakeet v2.

- Early close fired for every file. Accepted: new tab 14, scroll down 20, click 12 20, stop 19.
- p50 true end to early text: 521, 591, 593 and 612 ms (range 413 to 725), against about 1.3 to 1.4 s on the full path. The gate is 650 ms, a narrow margin.
- Fall-backs are recognition errors ("new time", "so" for "stop"), not rule rejections. No early text parsed to a different action than the full text.

## Not covered

- A live microphone (a human run is owed), executor time, and other voices.
- A pause of 350 ms or more inside a command acts on the first part ("click twenty ... three" clicks 20). `earlySilenceMs` 0 turns early close off.
