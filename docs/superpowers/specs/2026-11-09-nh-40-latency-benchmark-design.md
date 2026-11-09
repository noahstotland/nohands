# NH-40: A repeatable latency benchmark — Design

**Date:** 2026-11-09  **Ticket:** [NH-40](https://github.com/noahstotland/nohands/issues/40)
**Status:** Shipped
**Shipped:** in PR #102, with differences: [as-built](../as-built/2026-11-09-nh-40-latency-benchmark.md)

## Intent

Today the only way to tell whether a change slowed the voice-to-action path is to talk to the app and read the log.
`nohands-cli bench <dir>` replays a folder of recordings and prints a per-file table and p50 and p95 for each stage, so
latency work has before-and-after numbers.

## What changed since the ticket was written

The ticket's Today section predates NH-36, which added two things that decide this design:

- **`endpoint-test` and `EndpointReplay` already exist.** They replay audio through the real VAD, assembler, serial ASR
  loop and merge buffer, paced to real time. What's missing is the ticket's measurements, a directory argument and
  percentiles.
- **Short commands no longer wait for `silenceMs`.** They can close at about 350 ms. A benchmark that ran only VAD,
  assembler, transcriber and parser, as the ticket lists them, would report the roughly 1 s path for "new tab" that the
  app no longer takes.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the fixture change in [Audio](#audio).

Non-goals:

- Running in CI (ticket).
- Measuring the merge-window hold, the model path or the executor. The run is a dry run and stops at the parse.
- Pass/fail thresholds or stored baselines the tool compares against. It prints numbers and a person compares them.
- Changing `endpoint-test`'s output or meaning.

Anti-goals, which would make this a failure even if it prints a table:

- Numbers that describe a path the app doesn't take.
- Executing an action, or any network call. `bench` builds no resolver and no input synthesizer use.
- `swift test` needing the audio files or the models.

## Approaches

1. **Extend `EndpointReplay` and add a `bench` subcommand (chosen).** One replay path, the same one the app's pieces
   run, so early close and the merge rules are included. `Report` gains a few fields and the CLI adds the table.
2. **A new unpaced loop of VAD, assembler, transcriber, parser.** Faster to run and closest to the ticket's wording, but
   it skips early close and so measures the old path. It would also be a second replay to keep in step with the pipeline.
3. **A `--dir` flag on `endpoint-test`.** Less code, but the ticket names `bench`, and the two answer different
   questions: "did early close agree with the full pass" and "how long does each stage take".

## How it works

### Replay (`EndpointReplay.Report`, NoHandsMac)

`Report` gains:

| Field | Meaning |
|---|---|
| `closedBy` | `.early`, `.full`, or nil when no utterance closed |
| `speechEndLagMs` | Audio time of the chunk that closed the measured pass, minus the true end of speech |
| `asrMs` | Wall time of that pass's transcription |
| `actedText` | The last text released to the pipeline, else that pass's transcript |
| `utterances` | How many utterances closed in the file |

The **measured pass** is the accepted early pass if there is one, else the pipeline's transcription of the last closed
utterance. The existing reference re-transcription after the replay is not measured. Existing fields keep their meaning,
and `endpoint-test` prints what it prints today.

The replay stays paced to real time, because VAD and ASR overlap that way live. Sixteen short files take about a minute.

### Command (`bench <dir>`, nohands-cli)

- Exactly one argument. Reads `.wav` files directly in the directory (not subfolders, extension in any case), in sorted
  name order.
- Loads the config, then blanks `attentionWord` for the run. Recordings don't start with it, so every file would
  otherwise be "no match".
- Loads Parakeet with the configured version and runs two warm-up passes on one second of silence, before the first file.
  Load time is printed and counted in no stage.
- Parses `actedText` with `CommandGrammar(config: config.grammarConfig)` and times that call.
- `end-to-end = speechEndLagMs + asrMs + parseMs`.

Output, one row per file, then the summary:

```
silenceMs=1000 earlySilenceMs=350 asr=v2 attentionWord=ignored load=2310ms
click-forty-two.wav  close=early lag=312ms asr=141ms parse=0.02ms e2e=453ms utts=1 "click forty two" -> [.click(42)]
order-some-coffee.wav close=full lag=1180ms asr=210ms parse=0.04ms e2e=1390ms utts=1 "..." -> no match -> LLM
silent.wav           skipped: no utterance
summary: files=16 measured=15 skipped=1 early=12 full=3
lag        p50=312ms p95=1180ms
asr        p50=141ms p95=210ms
parse      p50=0.02ms p95=0.04ms
end-to-end p50=453ms p95=1390ms
```

The parse result reads as `nohands-cli parse` does: the actions, `rejected: <message>`, or `no match -> LLM`.

Failures:

- Missing directory, or no `.wav` in it: exit 1 with a message saying to record the files, pointing at
  `Tests/Fixtures/audio/README.md`.
- A file that can't be read, closes no utterance or transcribes to empty text: a `skipped:` row, left out of the
  percentiles, and the run continues.
- Nothing measured at all: exit 1 after the rows. Otherwise exit 0.

### Summary format (`LatencyStats`, NoHandsCore)

A new pure file, Foundation only:

- `percentile(_ values: [Double], _ p: Int) -> Double?`, nearest rank, nil when empty.
- `summaryLine(stage: String, values: [Double]) -> String` gives the lines above. Values under 10 ms print two decimals,
  others whole milliseconds. Empty values print `p50=n/a p95=n/a`.

### Audio

Three pieces, none needed by `swift test`:

- **`scripts/make-bench-audio.sh [outdir]`** generates the phrase set with `say`, as 16 kHz 16-bit mono WAV, into
  `.build/bench-audio/` by default. That folder is already ignored by git.
- **`Tests/Fixtures/audio/README.md`** lists the phrases and how to record them: one phrase per `.wav`, named after the
  phrase, in a quiet room, with under half a second of audio after the last word. `bench` accepts any audio file format
  AudioConverter reads as long as it is named `.wav`.
- **The phrase set**, 16 files: new tab, close tab, next tab, go back, copy, paste, scroll down ten, scroll up five,
  click forty two, click seven, stop, go to sleep, wake up, press command s, one dictation sentence, and "click ⟨600 ms
  pause⟩ forty two".

### Docs

- `README.md` CLI table and the `usage()` text gain `bench <dir>`.
- `docs/superpowers/as-built/2026-11-09-nh-40-latency-benchmark.md` holds the first run's numbers, as the ticket asks,
  with the Mac model, macOS version, audio source and config. It says plainly that the audio is synthesized.

## Tests

One table-driven test, `LatencyStatsTests`, for `summaryLine` and `percentile`: empty, one value, unsorted values where
nearest rank picks a known element, a sub-10 ms value and rounding. The replay and the command are manual checks because
they need the speech models. `swift test` touches no audio file and no model.

The manual check lists the `bench` run on this M1 Pro, the missing-directory exit, and a folder with one silent file.

## Left to the builder

- Row alignment and exact type names beyond those above.
- Swapping a phrase that `nohands-cli parse` doesn't accept for one from the README voice table, keeping the mix.
- The `say` voice and rate, as long as the script pins them so a re-run produces the same set on one Mac.

## Calls I made

1. **The baseline uses synthesized speech, and your recordings are still owed.** The ticket says you record the files,
   and an agent can't speak. The build gets its numbers from `say`, as NH-36 did. So `bench Tests/Fixtures/audio`, the
   ticket's exact acceptance command, will exit asking for recordings until you add them, and it goes in the PR's
   `Not proven` list. Synthesized speech has cleaner silence than a room, so the real numbers may differ.
2. **The `say` audio is generated, not checked in.** The repo is private today but has been prepared for open source
   under Apache-2.0. I couldn't confirm whether Apple's macOS licence allows redistributing `say` output, so the audio
   stays out of git and a script regenerates it. Recordings of your own voice can be committed if you want them there,
   which the ticket allows at a few MB.
3. **Early close is part of what's measured,** unlike the ticket's list of stages. Each row says whether it closed early
   or full.
4. **The percentiles pool early and full closes.** The ticket asks for one distribution, so p95 mostly reflects the full
   path. The `early=` and `full=` counts show the mix.
5. **With 10 to 20 files, p95 is close to the slowest file.** Nearest rank on 16 values picks the slowest one. Compare
   p50s, and treat p95 as a warning sign. I left out a repeat-runs flag because the ticket doesn't ask for one.
6. **End-to-end stops at the parse.** It leaves out the merge-window hold on phrases the grammar doesn't match, the model
   and the executor, because the ticket makes this a dry run.
7. **Lag starts at the same RMS "true end of speech" that NH-36's gates used,** so the numbers compare. Room noise above
   the 0.005 threshold can move that point late, and lag can then read low or negative. It's printed as is, not clamped.
   The recording notes exist to keep this from happening.
8. **The attention word is ignored during the run,** and the header says so. All other settings come from your config,
   so a changed `silenceMs` changes the results, which is why the header prints it.
9. **The dictation sentence is measured in command mode.** The replay has no dictation mode, so it shows as a full close
   and `no match -> LLM`.
10. **A file with a long pause counts once.** If a pause splits a file into two utterances, the row times the last one,
    and `utts=2` shows it.
11. **A skipped file doesn't fail the run.** It shows in the table and the `skipped=` count, and only a run with nothing
    measured exits non-zero.
12. **Two warm-up passes,** because `transcribe` already treats the first two runs as cold.
