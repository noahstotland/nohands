# NH-12: Optional attention word so stray speech is not acted on — Design

**Date:** 2026-11-05  **Status:** Draft  **Ticket:** [NH-12](https://github.com/noahstotland/nohands/issues/12)

## Intent

Everything the microphone hears in command mode is acted on, so a call, a video or someone in the room can
press keys. This change adds an optional attention word (config key `attentionWord`). When it is set, command
mode acts only on utterances that start with it: "computer, new tab" opens a tab, "new tab" on its own does
nothing. The word is matched in the transcript, not acoustically. Off by default, so nothing changes for
anyone who doesn't set it.

## Today

- `ModeMachine.route` (`Sources/NoHandsCore/ModeMachine.swift`) handles command, dictation and sleep. In
  command mode every transcript goes to `CommandGrammar.parse`, and an unmatched one becomes
  `.resolveWithLLM(phrase)`, which `VoicePipeline` turns into a task whose goal is that phrase.
- `MergeBuffer` (`Sources/NoHandsMac/MergeBuffer.swift`) holds a transcript for the merge window and appends
  the next one if speech resumes. `StopWords.isStop` is checked first and is never merged. While a transcript
  is held, `onHold` puts a `listening…` row on the prompt board.
- `VoicePipeline.busy` stops a running task when `StopWords.isStop(transcript)`; `process` turns a stop with no
  task into `.ignore`.
- README § Privacy says "There is no wake word."

## Approaches

1. **A pure `AttentionGate` in Core, applied in `ModeMachine` and consulted by `MergeBuffer` and
   `VoicePipeline`.** One rule, table-tested, no audio needed. Chosen.
2. **Strip in `VoicePipeline` before routing.** Rejected: the merge window would still merge stray speech into
   a real command and show stray words as `listening…`; the rule would also live in an untested Mac file.
3. **Acoustic wake-word model.** Out of scope per the ticket.

## Design

### Config (`NoHandsCore/AppConfig.swift`)

- `attentionWord: String = ""`, decoded with `decodeIfPresent`, default empty. A missing key, `null`, an
  empty string or one that is only spaces or punctuation means off.
- `load` normalizes it with `CommandGrammar.normalize` (lowercase, `.,!?` stripped, spaces collapsed). It may be
  several words ("hey mac"). A value of more than three words, or one that is itself a stop phrase
  (`StopWords.isStop`), is treated as off: a stop word as the attention word would make every "stop" look like an
  empty addressed command. This is not an error and does not flag the config.
- A new computed `attentionGate: AttentionGate` built from the normalized value.

### The rule (`NoHandsCore/AttentionGate.swift`, new)

```swift
public struct AttentionGate: Sendable, Equatable {
    public let words: [String]            // normalized tokens; empty = off
    public var isOn: Bool
    public enum Result: Equatable, Sendable {
        case addressed(String)            // word present; the rest of the transcript, original casing, word removed
        case wordOnly                     // the word and nothing else
        case notAddressed                 // gate on, word not at the start
        case off                          // gate off: use the transcript as is
    }
    public func check(_ transcript: String) -> Result
}
```

- Match on the leading tokens of `CommandGrammar.normalize(transcript)`: the first `words.count` tokens must
  equal `words`. Leading filler ("um", "uh", "er", "oh", "ok", "okay", "hey") before the word is skipped, so
  "um, computer, go back" is addressed. The word anywhere else ("tell the computer to go back") is
  `notAddressed`.
- The remainder is cut from the original transcript (so dictation-style casing reaches the model unchanged)
  with leading `,.!?:` and spaces trimmed. A remainder that is empty after normalization is `wordOnly`.
- Plural or possessive forms are not matched ("computers go back" is not addressed). ASR punctuation and case
  are ignored ("Computer. Go back." is addressed).
- `isStop(_ transcript:)` on the gate: `StopWords.isStop(transcript)`, or, when addressed, `StopWords.isStop` of
  the remainder. So "stop" and "computer, stop" both stop, with or without the gate on.

### Routing (`ModeMachine`)

- `ModeMachine.init` takes `attention: AttentionGate = .off`.
- **Command mode:** `check` first. `.off` → today's path. `.addressed(rest)` → today's path on `rest` (grammar,
  then `.resolveWithLLM` with the normalized `rest`, so the model never sees the word). `.wordOnly` →
  `.ignore(reason: "attention word only")`. `.notAddressed` → `.ignore(reason: "not addressed")`.
- A stop phrase is never gated: in command mode, if `StopWords.isStop(transcript)` the transcript takes today's
  path whatever the gate says (it becomes `.ignore(reason: "stop")` with no task, and `busy()` stops a running
  task before routing is reached).
- **Dictation mode:** unchanged; every utterance is text. The escape phrases ("stop dictating", "command mode")
  work without the word. They also work with it ("computer, stop dictating"): `isDictationEscape` and
  `isDictationCommand` accept an addressed remainder, so the pipeline and the merge buffer agree. Anything else
  that starts with the word is typed as text, word included.
- **Sleep mode:** unchanged; "wake up" works without the word, and "computer, wake up" works too.

### Pipeline (`NoHandsMac`)

- `VoicePipeline` builds the gate from `config.attentionGate` and passes it to `ModeMachine` and `MergeBuffer`.
- `busy()` uses `gate.isStop(job.transcript)` instead of `StopWords.isStop`, so "computer, stop" stops a task.
  Bare "stop" still stops it. The stop invariant is unchanged: a stop is never merged and always halts.
- `process`: `.ignore` with reason "not addressed" or "attention word only" reports nothing on the board and no
  HUD (as with sleep today); if the merge window already showed a row, it is cleared with `.ignored("")`. Logged
  as today, with the transcript under the private marker.
- `isComplete` checks the addressed remainder in command mode, so "computer, go back" still skips the merge
  window.

### Merge window (`MergeBuffer`)

- The stop check becomes `gate.isStop(text)`.
- In command mode with the gate on:
  - A new transcript that is addressed while something is pending flushes the pending one first instead of
    merging into it. Without this, stray speech followed within 500 ms by "computer, go back" would merge into
    "hello computer go back" and be ignored. The flushed stray text is then ignored by routing.
  - A pending transcript that is not addressed (and not the word alone) is not shown on the board: `onHold` is
    not called for it. It is still held, so "click the … computer back button" style accidents are not made
    worse, but it shows nothing.
  - The word alone ("computer" then a pause) is held for `mergeWindowUnfinishedMs` (1.5 s by default) like a
    dangling word, so "computer … go back" said in two breaths merges into one addressed command.
    It shows `listening…` like any held command.

### Docs

- README § Configuration: add `"attentionWord": ""` to the JSON sample and a paragraph: what it does, that it
  is matched in the transcript (so pick a word the recognizer hears reliably and you don't say in passing),
  that "stop", "wake up" and the dictation escapes work without it, and that dictation still types everything.
- README § Privacy: replace "There is no wake word." with a line saying the optional `attentionWord` makes
  command mode ignore speech that doesn't start with it; audio is still transcribed on the Mac, and dictation
  mode still types everything it hears.
- README voice command table: no new phrases (the word is a prefix, not a command). A one-line note under the
  table that, with `attentionWord` set, commands start with it.
- Architecture spec `2026-11-04-nohands-design.md` lists "Wake word" as a non-goal: add "(an optional
  transcript-matched attention word exists, NH-12)".

## Testing

- `AttentionGateTests` (Core, table-driven): off; word + command; word + punctuation ("Computer, go back.");
  word alone; word alone with punctuation; word inside a sentence; word after filler; multi-word attention word;
  plural not matched; remainder keeps original casing; `isStop` for "stop", "computer stop", "computer, never
  mind", "computer stop dictating" (not a stop).
- `ModeMachineTests` (one table): with the gate on, the ticket's cases: with the word, without it, the word
  alone, the word inside a sentence, "stop" without the word, a mode switch ("computer, start dictating" enters
  dictation; then plain words are typed; "stop dictating" without the word leaves; "go to sleep" without the
  word is ignored; asleep, "wake up" without the word wakes). Plus: `.resolveWithLLM` carries the remainder
  only (no attention word).
- `AppConfigTests`: default empty/off, normalization, a stop phrase and more than three words turn it off,
  `null` and a non-string type. (A non-string type throws like other keys today; see Calls.)
- `MergeBufferTests` (Mac, no audio): an addressed transcript after pending stray text is not merged into it;
  "computer, stop" is released at once; the word alone gets the unfinished window.
- Intent fixtures: unchanged and still pass; they bypass the gate (the model never sees the word).
- Manual (listed in the PR): set `attentionWord` to "computer", say "new tab" (nothing happens, no HUD), say
  "computer new tab" (a tab opens), say "stop" during a task (it stops).

## Non-goals

- Acoustic wake-word detection.
- A menu item to set or toggle the word (config file only, like the other keys).
- Gating dictation mode text.
- A timed "attention window" after the word that accepts several commands without repeating it.

## Risks

- The recognizer may mishear the word ("computer" as "commuter"), and the command is silently ignored. Silent
  is what the ticket asks for; the README tells users to pick a word the recognizer hears well.
- The flush-before-merge rule means stray speech just before an addressed command is never merged into it.
  That is the point, but a user who says "uh" in its own utterance before "computer …" loses nothing either,
  because the stray piece is ignored.

## Calls I made

- **The word alone waits 1.5 s for the rest** (`mergeWindowUnfinishedMs`) instead of being ignored outright, so
  "computer … go back" with a pause works. Ignored if nothing follows.
- **Stray speech is never merged into an addressed command**: a pending unaddressed piece is flushed (and
  ignored) when an addressed one arrives.
- **A few leading fillers are skipped** before the word ("um, computer, …", "hey computer"). Any other word
  before it means not addressed.
- **"computer, stop", "computer, wake up" and "computer, stop dictating" work too**, not just the bare
  phrases.
- **In dictation, text that starts with the word is typed in full**, word included. Only the escapes are
  recognized.
- **The attention word can be up to three words**; longer, or a stop phrase, is treated as off without
  flagging the config.
- **A non-string `attentionWord`** (e.g. a number) makes the config invalid like any other mistyped key today,
  so the menu flags it and defaults apply.
- **Nothing on the board or HUD for ignored speech**, matching sleep, and a stray piece held in the merge window
  is not shown as `listening…`.
- **No menu toggle**; config file only.
