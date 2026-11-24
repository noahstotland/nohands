# Dictation "scratch that" and "delete word" — Design

**Date:** 2026-11-04  **Ticket:** [NH-9](https://github.com/noahstotland/nohands/issues/9)  **Status:** Shipped
**Shipped:** in PR #21, with differences: [as-built](../as-built/2026-11-04-dictation-scratch.md)

## Intent

In dictation mode there is no way to take back what was just typed. Add two spoken edits:

- **"scratch that"** deletes the text the last dictated utterance typed, and does nothing when there is no record.
- **"delete word"** deletes back to the start of the previous word (`option delete`).

Both count only as the whole utterance so the same words inside a sentence are still typed, and both skip the merge-window delay. Non-goals: selecting or replacing earlier text, multi-level undo, "scratch that" in command mode (`undo` covers it).

## Approach

Repeat the existing `.pressKey(delete)` N times, with N recorded in core when the text was typed. No new action type, and `StopWords.isStop` is still checked first. Rejected: `command z` (undo granularity is app-defined) and a new action (touches schema, decoder, executors).

## Design

- **`DictationSession`** keeps a one-level record of the last insertion: its length in `Character`s ("\n\n" is 2) and the context before it. `scratch()` returns the count (nil when none), clears the record and restores the context, so the next utterance gets the right spacing and capitalisation. An utterance that formats to nothing leaves the record alone.
- **`ModeMachine.isDictationCommand`** matches the escape phrases plus both new ones on the whole normalised utterance.
- **Routing:** "scratch that" executes N delete presses, or is ignored with no record. "delete word" clears the record (`forgetLast()`) and executes `option delete`.
- **Mac:** `VoicePipeline.isComplete` uses `isDictationCommand` in dictation, so the phrases skip the merge window. Pause cancels the backspaces and clears the record.
- **README:** both phrases join the voice table.

## Testing

Table-driven core tests: phrase matching (exact true, embedded false), routing (N presses; a record-less "scratch that" ignored; spacing restored) and `MergeBufferTests`. Manual: in TextEdit, "scratch that" removes only the last sentence.

## Calls I made

- **One level only.** A stack is riskier after the user clicks elsewhere.
- **"delete word" clears the record**, so a following "scratch that" cannot delete too much. It does not adjust spacing context, so the next utterance's case or space may be off.
- **The record is taken when the text is routed, not confirmed typed.** If typing fails, "scratch that" can delete text never typed.
- **Dictation-only.** In command mode "delete word" keeps its grammar meaning.
