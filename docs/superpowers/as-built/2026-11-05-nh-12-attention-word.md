# As-built: Optional attention word

**Shipped:** in PR #27
**Ticket:** NH-12
**Spec:** [2026-11-05-nh-12-attention-word-design.md](../specs/2026-11-05-nh-12-attention-word-design.md)

## Differs from the spec

- The spec does not cover a task that is already running. Shipped: with the gate on in command mode, a not-addressed or word-only utterance heard while a task runs is dropped silently (logged as `ignore(not addressed)`), not held, so stray speech cannot replace a real held command. "stop" and "computer, stop" still halt the task.
- The spec says to replace "There is no wake word." in README § Privacy. Shipped: the sentence reads "There is no wake-word model.", followed by what the optional `attentionWord` does.
- A colon right after the word ("Computer: go back") does not count as addressed, because the normalizer only strips `.,!?`. The remainder trim still drops a leading colon.
- Merged with NH-10 (spell command, PR #26), which the spec predates: the merge window's long hold for a `spell` phrase and the "always wait" rule in `VoicePipeline.isComplete` apply to what follows the attention word, so "computer, spell kilo nine" waits out a pause between letters like a bare "spell" phrase. A rejected spell phrase stays a rejection when addressed.

## Checks that didn't run

- The intent fixtures (`nohands-cli eval scripts/intent-eval*.json`) need a model backend and did not run.
- The manual checks in the spec § Testing (say "new tab", "computer new tab", "stop" during a task) need the microphone and Accessibility.
