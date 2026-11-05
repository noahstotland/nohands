# As-built: Dictation "scratch that" and "delete word"

**Shipped:** in PR #21
**Ticket:** NH-9
**Spec:** [2026-11-04-dictation-scratch-design.md](../specs/2026-11-04-dictation-scratch-design.md)

## Differs from the spec

- The spec says the only Mac change is one line in `VoicePipeline.isComplete`. `MergeBuffer.transcript` also had to use `ModeMachine.isDictationCommand`: it merges a new transcript into the held one before `isComplete` is asked, so without the change "scratch that" spoken inside the merge window would be appended to the held fragment and typed. It now flushes the held text first and passes the phrase on alone, like "stop dictating".
