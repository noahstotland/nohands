# Dictation "scratch that" and "delete word" — Design

**Date:** 2026-11-04  **Ticket:** [NH-9](https://github.com/noahstotland/nohands/issues/9)  **Status:** spec, awaiting approval

## Intent

In dictation mode there is no way to take back what was just typed by voice. Add two spoken edits:

- **"scratch that"** deletes the text the last dictated utterance typed.
- **"delete word"** deletes back to the start of the previous word (`option delete`).

## Goals / non-goals

- **Goals:** both phrases work in dictation mode, recognised only as the whole utterance (like "stop dictating"),
  so the same words inside a sentence are still typed. "scratch that" removes exactly the characters the last
  utterance typed and does nothing when there is no record. Both go through without the merge-window delay.
  README voice table gets both rows.
- **Non-goals:** selecting or replacing earlier text ("select the last sentence"); multi-level undo
  ("scratch that" twice removes only one utterance, see Calls); "scratch that" in command mode (the existing
  `undo` phrase covers that).

## Approaches

1. **Send `command z`.** Rejected: undo granularity is app-defined (TextEdit may undo the whole session, a
   browser field may undo nothing), so the result is unpredictable.
2. **New `deleteBackward(count)` action.** Rejected: a new `Action` case touches the intent schema, decoder,
   executor, harness executor and `ActionSummary` for something the grammar already expresses.
3. **Repeat the existing `.pressKey(delete)` action N times**, with N recorded in core when the text was
   produced. Chosen: no new action type, no executor change, all logic in `NoHandsCore` and unit tested.

## Design

### Core (`Sources/NoHandsCore`)

**`DictationSession`** (`DictationFormatter.swift`) gains a one-level record of the last insertion:

- `next(_:)` already returns the exact string that will be typed (including the leading space it may add). It now
  also remembers that string's length in `Character`s (`typedCount`) and the `last` context from before it.
- New `mutating func scratch() -> Int?`: returns the recorded count (nil when there is none, or it is 0), clears
  the record, and restores `last` to the context before the scratched insertion so the next utterance gets the
  right spacing and capitalisation (scratch "World." after "Hello." and the next utterance starts a capitalised
  sentence with a leading space again).
- New `mutating func forgetLast()`: clears the record (used by "delete word"; afterwards the record no longer
  matches what is on screen).
- An utterance that formats to nothing (`next` returns "") leaves the existing record alone.

Length is counted in `Character`s (grapheme clusters), which matches one Backspace per character in standard
macOS text views; "\n\n" from "new paragraph" counts as 2.

**`ModeMachine`** (`ModeMachine.swift`):

- New `public static func isDictationCommand(_ transcript: String) -> Bool`: true for the escape phrases
  (`isDictationEscape`, unchanged) plus `scratch that` and `delete word`, compared on the normalised whole
  utterance (`CommandGrammar.normalize`, so "Scratch that." matches and "please scratch that" does not).
- In `route(_:)`, `.dictation` case, after the escape check:
  - `scratch that` → `.execute(Array(repeating: .pressKey(KeyChord(.delete)), count: n))` where
    `n = session.scratch()`; with no record → `.ignore(reason: "nothing to scratch")`.
  - `delete word` → `session.forgetLast()`, then `.execute([.pressKey(KeyChord(.delete, [.option]))])`
    (the same chord the command-mode grammar already uses for "delete word").
- Entering dictation already starts a fresh `DictationSession`, so the record never survives leaving dictation.

### Mac (`Sources/NoHandsMac`) — kept minimal for NH-3

**`VoicePipeline.swift`: one line in one function, `VoicePipeline.isComplete(_:mode:grammar:)`.** The
`.dictation` case changes from `ModeMachine.isDictationEscape(transcript)` to
`ModeMachine.isDictationCommand(transcript)`, so the two phrases skip the merge window and are never appended to
a held dictation fragment. No other `VoicePipeline` function changes. `OverlayController.swift` is not touched.
NH-3 (`feat/nh-3-prompt-board-search`) also edits `VoicePipeline.swift`; this single-line edit should merge
cleanly unless NH-3 changes `isComplete` itself.

No executor or input-synthesizer change: `.pressKey` is already executed in order with `Task` cancellation checks
between actions, so a spoken "stop" still halts a long backspace run.

### Docs

`README.md` voice command table, two rows next to `start dictating` / `stop dictating`:

| `scratch that` (dictation) | Deletes what your last dictated phrase typed |
| `delete word` (dictation) | Deletes the previous word |

and one sentence in the "Pausing mid-command" paragraph: "scratch that" and "delete word" also go through on their
own in dictation.

## Safety and invariants

- No network, no new action type, no decoder or guard bypass: the actions are produced by the on-device grammar
  path only and are the existing `.pressKey` case.
- Stop handling is unchanged: `StopWords.isStop` is checked first in `isComplete`, and the executor checks
  cancellation between each backspace.
- The backspaces go to the frontmost app, like every dictated keystroke.

## Testing

Core (table-driven, `Tests/NoHandsCoreTests`):

- `ModeMachine.isDictationCommand`: exact phrases and ASR variants ("Scratch that.", "delete word") are true;
  longer text containing them ("I said scratch that", "delete word count") is false; command mode is unaffected.
- `ModeMachine` routing in dictation: after utterances with punctuation, a leading space and "new paragraph",
  "scratch that" yields exactly `typedCount` delete presses; a second "scratch that" and a "scratch that" with no
  prior utterance are ignored; "delete word" yields one `option delete` and clears the record; the utterance after a
  scratch gets the restored spacing/capitalisation.
- `Tests/NoHandsMacTests/MergeBufferTests.isCompleteCoversStopsAndDictationEscapes`: add the two phrases (true in
  dictation, `scratch that` false in command mode).

Manual (listed in the PR): dictate two sentences in TextEdit, say "scratch that": the second is gone and the first
is intact; "delete word" removes the last word; "I said scratch that" is typed.

## Calls I made

- **One level only.** A second "scratch that" does nothing rather than removing the utterance before. Multi-level
  would need a stack and is riskier if the user has clicked elsewhere or typed by hand; one level matches the ticket.
- **"delete word" clears the scratch record**, so "delete word" then "scratch that" does nothing (the recorded
  count no longer matches the screen and would delete too much).
- **"delete word" does not adjust spacing/capitalisation context** for the next utterance; the session does not know
  what option-delete removed. Worst case the next utterance's first letter case or leading space is off.
- **The record is taken when the text is routed, not when it is confirmed typed.** If typing fails (e.g. text too
  long, denied Accessibility), a later "scratch that" can delete characters that were never typed. Feeding executor
  results back into the mode machine would touch more of `VoicePipeline`, which NH-3 also changes.
- **Repeated `.pressKey(delete)` actions** rather than a new action or `command z` (see Approaches). A 300-character
  utterance becomes 300 key events and one log line listing 300 `pressKey`s.
- **Dictation-only.** In command mode "scratch that" still goes to the model as today; "delete word" keeps its
  existing command-mode grammar meaning.
- **HUD text** for both is whatever the pipeline already shows for executed actions; no new copy.
