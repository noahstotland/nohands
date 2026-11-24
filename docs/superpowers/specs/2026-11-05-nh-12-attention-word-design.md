# NH-12: Optional attention word so stray speech is not acted on — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-12](https://github.com/noahstotland/nohands/issues/12)
**Shipped:** in PR #27, with differences: [as-built](../as-built/2026-11-05-nh-12-attention-word.md)

## Intent

Everything heard in command mode is acted on, so a call, a video or someone in the room can press keys. The optional config key `attentionWord` makes command mode act only on utterances that start with it: "computer, new tab" opens a tab, "new tab" alone does nothing. It is matched in the transcript, not acoustically. Off by default.

## Approach

Chosen: a pure `AttentionGate` in Core, applied in `ModeMachine` and consulted by `MergeBuffer` and `VoicePipeline`. One rule, table-tested, no audio.

Rejected: stripping in `VoicePipeline` (the merge window would still merge stray speech into a real command).

## Design

- **Config:** `attentionWord`, default empty, normalized with `CommandGrammar.normalize`. Missing, empty or punctuation-only means off. More than three words, or a stop phrase, is also off (it would make every "stop" an empty addressed command), without flagging the config. A non-string value is invalid like any mistyped key.
- **Gate result:** `addressed(rest)`, `wordOnly`, `notAddressed`, `off`.
  - The leading tokens of the normalized transcript must equal the word. Filler (`um`, `uh`, `er`, `oh`, `ok`, `okay`, `hey`) before it is skipped; the word anywhere else is not addressed.
  - `rest` keeps the original casing. Plurals do not match; punctuation and case are ignored.
  - `isStop` accepts bare "stop" and "computer, stop", gate on or off.
- **Command mode:** `.off` takes today's path. `.addressed(rest)` takes it on `rest`, so the model never sees the word. `.wordOnly` and `.notAddressed` are ignored. A stop phrase is never gated.
- **Dictation and sleep:** unchanged. Dictation types everything, word included, except the escapes ("stop dictating", "command mode"), which work with or without the word. "wake up" works either way.
- **Pipeline:** `busy()` uses `gate.isStop`, so "computer, stop" halts a task; a stop is never merged. Ignored speech shows nothing on the board or HUD.
- **Merge window, gate on:**
  - An addressed transcript arriving while something is pending flushes the pending one first (it is then ignored). Otherwise stray speech plus "computer, go back" within 500 ms would merge and be ignored.
  - A pending unaddressed transcript is held but not shown.
  - The word alone is held for `mergeWindowUnfinishedMs` (1.5 s), so "computer ... go back" in two breaths works.
- **Docs:** README configuration and privacy ("no wake word" becomes "optional `attentionWord`"; audio is still transcribed on the Mac).

## Tests

- Tables for the gate, the mode machine with the gate on (mode switches, only the remainder reaches the model), config edge cases and the merge buffer (flush before an addressed piece, immediate stop, word-alone window). Intent fixtures unchanged. Manual, in the PR: "new tab" does nothing, "computer new tab" opens one, "stop" still stops a task.

## Non-goals

Acoustic wake-word detection, a menu toggle, gating dictation text, a timed attention window.

## Risks

- A misheard word (`commuter`) means a silently ignored command. The ticket asks for silent; the README says to pick a word the recognizer hears well.
- Stray speech after an addressed command inside the window still joins it; only speech before is split off.

## Calls I made

- The word alone waits 1.5 s for the rest instead of being ignored.
- Stray speech is never merged into an addressed command.
- A few leading fillers are skipped; any other word before it means not addressed.
- "computer, stop", "computer, wake up" and "computer, stop dictating" work, not just the bare phrases.
- In dictation, text starting with the word is typed in full.
