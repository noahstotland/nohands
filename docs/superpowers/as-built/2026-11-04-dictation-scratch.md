# As-built: Dictation "scratch that" and "delete word"

**Shipped:** in PR #21
**Ticket:** NH-9
**Spec:** [2026-11-04-dictation-scratch-design.md](../specs/2026-11-04-dictation-scratch-design.md)

## Differs from the spec

- The spec says the only Mac change is one line in `VoicePipeline.isComplete`. `MergeBuffer.transcript` also had to use `ModeMachine.isDictationCommand`: it merges a new transcript into the held one before `isComplete` is asked, so without the change "scratch that" spoken inside the merge window would be appended to the held fragment and typed. It now flushes the held text first and passes the phrase on alone, like "stop dictating".
- The spec says a spoken "stop" halts a long run of backspaces. It does not: dictation actions run in the serial consumer, so "stop" is the next job, and the backspaces are posted back to back and finish first. The spec's wording is corrected; Pause still cancels.
- The spec does not clear the scratch record on pause. `VoicePipeline.stop()` now calls `ModeMachine.forgetDictationRecord()`, so after a pause "scratch that" does nothing instead of deleting text it never typed (an utterance routed but cancelled, or text the user typed by hand meanwhile).

## Checks that didn't run

- The five manual checks listed in the PR (dictate two sentences in TextEdit and say "scratch that"; "delete word"; "I said scratch that" is typed; a 100+ character utterance scratched in a browser text field, to confirm no key events are dropped; "scratch that" after pausing and resuming deletes nothing). They need a microphone and Accessibility.
