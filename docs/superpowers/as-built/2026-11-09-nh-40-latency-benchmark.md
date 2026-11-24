# NH-40: A repeatable latency benchmark — As built

**Shipped:** in PR #102
**Ticket:** [NH-40](https://github.com/noahstotland/nohands/issues/40)
**Spec:** [design](../specs/2026-11-09-nh-40-latency-benchmark-design.md)

## Differs from the spec

- **A spoken "stop" prints `-> stop`, not `no match -> LLM`.** The grammar does not parse "stop" (the pipeline halts on it first), so the row uses `config.attentionGate.isStop`.
- **The measured pass is the latest close in the file by audio time,** not the accepted early pass. When a pause splits a file, the last utterance is timed (spec call 10).
- **`LatencyStats.format(_:)` is public,** so file rows and summary lines share millisecond formatting.
- **A file that throws prints `skipped: <error description>`.**
- **File names are padded to the longest,** and actions print in Swift's debug form, as `nohands-cli parse` does.
- **"No network call" means no Claude or Ollama call.** The first run downloads the speech models.
- **FluidAudio `[INFO]` lines appear between rows,** because the replay builds a fresh VAD per file.

## First run

Synthesized speech (`scripts/make-bench-audio.sh`: `say`, Samantha, rate 180, 16 kHz mono), then `nohands-cli bench .build/bench-audio`. The ticket's recordings are still owed, so `bench Tests/Fixtures/audio` exits asking for them. Real rooms have noisier silence, so real numbers may differ.

- M1 Pro, 16 GB, macOS 14.5, debug build, Parakeet v2, defaults (`silenceMs=1000`, `earlySilenceMs=350`).
- Model load plus two warm-up passes took 4373 ms, counted in no stage. The run took about a minute (paced to real time).

Summary line: `files=16 measured=16 skipped=0 early=15 full=1`.

| Stage | p50 | p95 |
|---|---|---|
| lag | 360 ms | 1068 ms |
| asr | 140 ms | 166 ms |
| parse | 0.02 ms | 0.05 ms |
| end-to-end | 501 ms | 1234 ms |

- Fifteen files closed early, at about 350 ms of silence plus up to one 256 ms chunk. The one full close is the dictation sentence (not a command), which sets every p95. Compare p50s.
- `click-pause-forty-two.wav` did not split: its 600 ms pause is shorter than `silenceMs` and the early pass on "click" was not accepted.
- Lag includes the VAD chunk size (4096 samples, 256 ms), so values of 308 to 564 ms differ by where the true end falls in a chunk.

## Checks that ran

- `swift build` clean. `swift test`: 458 pass, with no audio, models or permissions.
- `bench` on a nonexistent or empty folder exits 1 with a message. On one silent file it prints `skipped: no utterance`, percentiles `n/a`, exit 1.
