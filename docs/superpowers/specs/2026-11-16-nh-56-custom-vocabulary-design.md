# NH-56: Custom vocabulary: Design

**Date:** 2026-11-16  **Ticket:** [NH-56](https://github.com/noahstotland/nohands/issues/56)
**Status:** Draft

## Intent

Parakeet hears "Raptors" as "raptures" and "StreamEast" as "stream east", and every command that uses those words fails. This lets the user list their words once in `config.json`; NoHands swaps each misheard spelling for the right one in every transcript before anything acts on it.

Non-goals: acoustic adaptation; FluidAudio vocabulary boosting (see Decision); a spoken "that's spelled …" correction (follow-up); vocabulary in app packs; editing the list from the menu.

Anti-goals: an entry that turns a stop into something else, or something else into a stop; matches inside a word ("raptures" must not touch "enraptured"); a substitution that is fed back into itself; the list touching the network.

## Decision

A pure text rewrite in `NoHandsCore`, run on each transcript as it leaves the recognizer. It works with every ASR model version and costs microseconds.

FluidAudio vocabulary boosting is not used. In the resolved revision (e396cf7) `configureVocabularyBoosting` exists only on `UnifiedAsrManager`, `StreamingUnifiedAsrManager` and `SlidingWindowAsrManager`. The batch `AsrManager` that `ParakeetTranscriber` uses has no hook, and boosting also needs a separate CTC model download. Moving to another manager is its own ticket; the PR says so.

## How it works

### Config

```json
"vocabulary": [
  { "hear": "raptures", "say": "Raptors" },
  { "hear": ["stream east", "streem east"], "say": "StreamEast" }
]
```

- `hear` is a string or a list of strings; `say` is a string.
- `AppConfig.vocabulary` holds the cleaned list as a `Vocabulary` value. Decoding never fails the config: a `vocabulary` that is not a list is ignored, and each bad entry is skipped.
- An entry is skipped when `say` is missing or empty, no `hear` spelling is left after cleaning, or a `hear` or `say` contains a stop word (`stop`, `cancel`, `never mind`/`nevermind`, `abort`, `halt`, as in `StopWords`). A single bad `hear` spelling is dropped and the rest of the entry kept.
- Limits: 200 entries (the rest skipped), a `hear` spelling of at most 5 words, a `say` of at most 100 characters.
- `load` records how many entries it skipped. At launch the app logs one line when that is not zero: `vocabulary: skipped 3 entries (see docs/configuration.md)`. The log names no words.

### Matching (`Vocabulary.apply`)

- The transcript is split into words on whitespace. Each word's leading and trailing punctuation is set aside, so `raptures,` matches `raptures` and comes out `Raptors,`.
- At each word, the longest `hear` (by word count) that matches the next words wins; within the same length, the first entry in the file wins. Words compare case-insensitively and must match whole. Only whitespace may sit between the words of a multi-word match; punctuation inside it breaks the match.
- The leading punctuation of the first matched word and the trailing punctuation of the last are kept around `say`. Words between matches are copied unchanged, spacing included.
- One left-to-right pass; replaced text is never scanned again, so `say` can contain its own `hear` without looping.
- An empty list returns the transcript as is.

### Where it runs

- `VoicePipeline.runASR` applies it to the early pass and the full pass, before the merge buffer. The merge buffer's completeness check, the attention word, the grammar, dictation and the model all see the corrected text, as do the HUD and the command log.
- A transcript that is a stop (`AttentionGate.isStop`) is passed on unchanged. With the stop-word filter on entries, the list can neither hide nor make a stop.
- Dictation types `say` as written ("Raptors", "StreamEast"). In command mode `search for raptures` becomes `search for Raptors`, and the model gets the corrected phrase.
- `nohands-cli transcribe` and `parse` do not apply it (they are dev probes of the raw recognizer and grammar).

### Tests

- Core, one table: replacement in the middle, at the start, next to punctuation, case-insensitive, no partial-word match, multi-word `hear`, longest `hear` wins, no rescan of replaced text.
- `AppConfigTests`, one table: string and list `hear`, entries skipped for each rule, the 200 cap, the skipped count, a non-list `vocabulary` ignored.
- `VoicePipelineTests`: `runASR` with a fake transcriber hearing "search for raptures" emits "search for Raptors" to the merge buffer, and a stop transcript passes unchanged.

### Docs

- `docs/configuration.md`: a `vocabulary` row and a bullet with the Raptors example, the rules and the limits.
- README: no change. Its Configuration section already points to `docs/configuration.md`.
- `docs/voice-commands.md`: no change (no new phrase).

## Calls I made

- FluidAudio boosting is left out: the batch manager in the resolved revision has no hook, and it needs an extra CTC model download.
- An entry whose `hear` or `say` contains a stop word is skipped, and stop transcripts are never rewritten. This keeps the stop invariant even with a careless list.
- The rewrite runs before the attention word check, so a misheard attention word can be fixed by an entry too.
- Limits I picked: 5 words per `hear`, 100 characters per `say` (the ticket gave only the 200-entry cap).
- Duplicate `hear` spellings: the first entry in the file wins.
- Punctuation between words breaks a multi-word match ("stream, east" stays as heard).
- The skipped-entries log line names a count only, never words, because transcripts are private.
- The CLI's `transcribe` and `parse` stay raw.
- The list is read at launch like the other keys; no live reload.
