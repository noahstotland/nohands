# NH-60 Spoken Feedback Implementation Plan

> **For agentic workers:** use subagent-driven-development or executing-plans; steps use checkboxes.

**Goal:** NoHands can say task outcomes, and at level `all` questions and readings, out loud, without hearing itself.

**Architecture:** Pure wording, level and echo rules in `NoHandsCore`; a `@MainActor` `FeedbackSpeaker` in `NoHandsMac` plays system speech through the capture engine; the pipeline feeds it cues and cuts it on stop.

**Tech Stack:** Swift 6 strict concurrency, AVFoundation (`AVSpeechSynthesizer.write`, `AVAudioPlayerNode`), SwiftPM tests.

**Spec:** `docs/superpowers/specs/2026-11-16-nh-60-spoken-feedback-design.md`

## Global Constraints

- No `@unchecked Sendable` or `@preconcurrency` added; no AppKit/network in Core. (`MicrophoneCapture` already exists as is; do not widen its isolation workarounds.)
- Off by default: with `speakFeedback` `off`, no synthesizer and no audio node is created.
- Private text (rewrite results, clipboard, selected or field text, anything a task read) is spoken only at `all`, cut at 300 characters; below `all` it is "Done." / "Stuck." / "Failed.".
- A stop phrase is checked before the echo filter and always acts; it is never merged into another utterance.
- Every new phrase is added to `docs/voice-commands.md` in the same PR; no existing phrase changes meaning.
- Tests per `AGENTS.md` § Testing: table-driven, no microphone/AX/model.

## Review Focus

- A transcript equal to the spoken line must not run as a command or answer a question (SelfEcho table).
- "stop", "stop dictating", "stop the music" keep their meaning after the new grammar rows (grammar table).
- `speakFeedback` with a bad value or non-string decodes to `off` (config table).
- Private lines at `outcomes` never contain the detail (SpokenFeedback table).
- Dictation and sleep never speak (pipeline test with a fake speaker).

---

### Task 1: Level, config key and menu patch (Core)

**Files:** Modify `Sources/NoHandsCore/AppConfig.swift`; Create `Sources/NoHandsCore/SpokenFeedback.swift` (enum here); Modify `Sources/NoHandsCore/BackendMenu.swift` or add `SpeakMenu` beside it; Test in `Tests/NoHandsCoreTests`.

**Interfaces:** Produces `public enum SpeakLevel: String, Codable, Sendable, CaseIterable { case off, outcomes, all }`; `AppConfig.speakFeedback: SpeakLevel = .off`, lenient decode (missing, unknown, non-string → `.off`); `SpeakMenu.merged(existing: Data?, level: SpeakLevel) throws -> Data` via `ConfigPatch.merged(existing:key:"speakFeedback",value:)`.

- [ ] Failing test: one table for config decode (missing, each value, `"loud"`, `5`) and one for the patch writing only that key.
- [ ] Implement; run `swift test --filter` for them.
- [ ] Commit `feat(core): speakFeedback config key (NH-60)`.

### Task 2: SpokenFeedback wording (Core)

**Files:** `Sources/NoHandsCore/SpokenFeedback.swift`; test.

**Interfaces:** `public enum FeedbackCue: Equatable, Sendable { case status(PromptStatus, carriesPrivateText: Bool); case question(String); case confirm(verb: String) }`; `SpokenFeedback.maxSpoken = 300`; `SpokenFeedback.line(for: FeedbackCue, level: SpeakLevel) -> String?` exactly per the spec table, with the spec's speakable rules (strip trailing `(N step[s])` and `· N steps`, `" · "`→`": "`, drop `…`, collapse whitespace, capitalize, add `.`/`?`, cut at 300 on a word boundary, empty → nil).

- [ ] Failing table test with every spec row (rows quoted verbatim from the spec), plus never-spoken statuses at each level and `off`.
- [ ] Implement; tests pass; commit `feat(core): spoken feedback wording (NH-60)`.

### Task 3: SelfEcho filter (Core)

**Files:** `Sources/NoHandsCore/SelfEcho.swift`; test.

**Interfaces:** `public struct SpokenLine: Equatable, Sendable { text: String; start: ContinuousClock.Instant; end: ContinuousClock.Instant? }`; `SelfEcho.isEcho(transcript: String, utteranceEnd: ContinuousClock.Instant, spoken: SpokenLine?, tail: Duration = .seconds(1)) -> Bool`: true when the utterance ended in `[start, (end ?? now-open) + tail]` and ≥70% of its normalized words (all, if fewer than three) are words of the line. Use `CommandGrammar.normalize`.

- [ ] Failing table test: inside window echo; same words after window passes; different command passes; short transcript needs all words; `end == nil` (still speaking) counts as open.
- [ ] Implement; commit `feat(core): drop own voice heard as speech (NH-60)`.

### Task 4: Grammar phrases (Core)

**Files:** `Sources/NoHandsCore/Action.swift`, `CommandGrammar.swift`, `ActionSummary.swift`, `SettlePolicy.swift`, `SpokenFreeText.swift`, `Mac/PipelineText.swift` and every other exhaustive `Action` switch the compiler flags; test.

**Interfaces:** `Action.setSpokenFeedback(SpeakLevel)`, grammar only (no decoder kind). Phrases: `spoken feedback on`, `turn on spoken feedback` → `.outcomes`; `spoken feedback off`, `turn off spoken feedback` → `.off`; `spoken feedback all`, `speak everything` → `.all`. They sit in the exact table and are not stop phrases.

- [ ] Failing grammar table including unchanged rows `stop`, `stop dictating`, `stop the music`, `turn on the lights` (still nil/unchanged vs main).
- [ ] Implement; `swift build` clean; commit `feat(core): spoken feedback voice phrases (NH-60)`.

### Task 5: Playback, speaker and pipeline (Mac)

**Files:** `Sources/NoHandsMac/MicrophoneCapture.swift` (add `play(_ buffer: AVAudioPCMBuffer)`, `cancelPlayback()`, `var echoCancellationActive: Bool`; one `AVAudioPlayerNode` attached to `mainMixerNode` on first use, re-attached on configuration rebuild); create `FeedbackSpeaker.swift`; modify `VoicePipeline.swift`, `TaskRunner.swift`, `ActionExecutor*.swift` (handle `.setSpokenFeedback` through a closure/protocol), `Sources/NoHands/AppDelegate.swift` (Speak Feedback submenu: Off/Outcomes/All, checked, writes via `SpeakMenu.merged`, applies live).

**Interfaces:** `protocol FeedbackSpeaking: Sendable`-or-`@MainActor` with `speak(_ line: String, cue kind)`, `cut()`, `var current: SpokenLine?`; `FeedbackSpeaker` uses `AVSpeechUtterance.prefersAssistiveTechnologySettings = true`; `synth.write` buffers go to `MicrophoneCapture.play` when echo cancellation is active, else `synth.speak`. `TaskRunner` exposes whether any read action ran (`carriesPrivateText`); a rewrite row always does. Pipeline: speak each task-slot final status once per row id; question/confirm at `all`; cut on stop phrase (before busy handling, task still cancelled as today), on any non-echo transcript, new task, `stop()`/`pause()`, entering dictation/sleep; never speak in dictation/sleep/paused; before routing, drop transcripts where `SelfEcho.isEcho` is true unless `attention.isStop`; log `ignore(own voice)`. Log one line per spoken line (kind and count; text only with the private marker).

- [ ] Failing pipeline tests with a fake `FeedbackSpeaking`: done spoken once; stop cuts and still cancels a running task; echoed question text is not the answer; dictation speaks nothing.
- [ ] Implement; `swift build` clean (strict concurrency); `swift test` green.
- [ ] Commit `feat(mac): spoken feedback (NH-60)`.

### Task 6: Docs

**Files:** `docs/configuration.md` (`speakFeedback` row, applies without restart, note by `echoCancellation`), `docs/voice-commands.md` (new phrases; stop also cuts NoHands' voice), `docs/using-nohands.md` (submenu), `docs/privacy.md` (Spoken feedback bullet).

- [ ] Write per spec § Docs; commit `docs: spoken feedback (NH-60)`; push.
