# NH-12 Attention Word Implementation Plan

**Goal:** An optional `attentionWord` config key. When set, command mode acts only on utterances that start with it; everything else is ignored silently. Off by default.

**Spec:** `docs/superpowers/specs/2026-11-05-nh-12-attention-word-design.md`. Read it first; it is the source of truth for the rules.

**Constraints:** Swift 6 strict concurrency (no `@unchecked Sendable`, no `@preconcurrency`). `NoHandsCore` stays pure (no AppKit, no network). A spoken "stop" is never merged and always halts the running task, with or without the word. `swift test` needs no permissions and no Ollama. Never edit `scripts/intent-eval*.json`. `swift build` and `swift test` green after each task. Do not commit; the parent commits.

## Task 1: `AttentionGate` and config (NoHandsCore)

- [ ] New `Sources/NoHandsCore/AttentionGate.swift` as in the spec: `words`, `isOn`, `Result` (`addressed(String)`, `wordOnly`, `notAddressed`, `off`), `static let off`, `init(configured: String)` (normalizes with `CommandGrammar.normalize`; off when empty, more than three words, or `StopWords.isStop`), `check(_:)`, `isStop(_:)`.
- [ ] `check`: tokens of the transcript are matched against `words` at the start, after skipping leading fillers (`um uh er oh ok okay hey`). Cut the remainder from the original transcript after the chunk holding the last word token, so casing is kept; trim leading `,.!?:` and whitespace. Empty after normalization is `.wordOnly`. The word elsewhere, plural or possessive forms are `.notAddressed`. Walk the original string's whitespace-separated chunks and map each to its normalized token (skip chunks that normalize to empty) to find the cut point.
- [ ] `AppConfig.attentionWord: String = ""` with a doc comment, in `CodingKeys` and `init(from:)` (`decodeIfPresent ?? default`; `null` is absent; a non-string throws like other keys). `load` stores the normalized value, or `""` when the gate would be off. Computed `attentionGate: AttentionGate`.
- [ ] Tests: `AttentionGateTests` (table-driven, per spec § Testing) and extend `AppConfigTests` (default off, normalization, stop phrase and four-word value turn it off, `null`, non-string throws).

## Task 2: Routing (NoHandsCore)

- [ ] `ModeMachine.init(grammar:mode:attention: AttentionGate = .off)`.
- [ ] Command mode: per spec § Routing (`.off` unchanged; `.addressed(rest)` routes `rest` through grammar then `.resolveWithLLM(normalized rest)`; `.wordOnly` is `.ignore(reason: "attention word only")`; `.notAddressed` is `.ignore(reason: "not addressed")`). A transcript where `StopWords.isStop(transcript)` takes today's path whatever the gate says.
- [ ] Dictation and sleep: unchanged, except the escape phrases / dictation commands / "wake up" are also accepted as an addressed remainder. `isDictationEscape` and `isDictationCommand` gain a defaulted `attention: AttentionGate = .off` parameter. Anything else starting with the word is typed as text, word included.
- [ ] `ModeMachineTests`: one table with the gate on, per spec § Testing.

## Task 3: Pipeline and merge window (NoHandsMac)

- [ ] `VoicePipeline`: build `config.attentionGate`, pass to `ModeMachine`, `MergeBuffer` and `isComplete` (new `attention` parameter, defaulted so existing callers and tests compile). `isComplete` uses `gate.isStop`, and in command mode checks the addressed remainder against the grammar.
- [ ] `VoicePipeline.busy`: use `gate.isStop(job.transcript)`. Also: in command mode with the gate on, an utterance that is `.notAddressed` or `.wordOnly` while a task runs is dropped (not held, so it cannot replace a real held command); clear its row with `.ignored("")` if `job.shown`; log it as ignored. (This goes beyond the spec text; list it under "Differs from spec" in the PR.)
- [ ] `process`: no change expected; `.ignore` already reports nothing and clears a shown row. Check this and say so if true.
- [ ] `MergeBuffer`: `gate` init parameter (default `.off`). Stop check becomes `gate.isStop(text)`. In command mode with the gate on: an addressed or word-only transcript arriving while something is pending flushes the pending one first; a pending transcript whose merged text is `.notAddressed` is held but `onHold` is not called; the word alone is held for the unfinished window (not complete, shown as `listening…`). Dictation and sleep behave as today.
- [ ] `MergeBufferTests` (no audio): addressed after stray text is not merged into it; "computer, stop" released at once; word alone gets the unfinished window and merges with the next piece.

## Task 4: Docs

- [ ] README: § Configuration sample key and paragraph, § Privacy line (replace "There is no wake word." with the accurate statement, keeping the rest of the paragraph true), one-line note under the voice command table. Architecture spec `2026-11-04-nohands-design.md` non-goal line, as in the spec.

## Verify

`swift build`, `swift test`, and the two intent fixture runs from `docs/agents/project.md` if the CLI can run without a model (otherwise say they did not run). Manual checks (spec § Testing) go in the PR as not run.
