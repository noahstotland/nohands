# NH-12 Attention Word Implementation Plan

**Goal:** An optional `attentionWord` config key. When set, command mode acts only on utterances starting with it; the rest is ignored silently. Off by default.

**Spec:** `docs/superpowers/specs/2026-11-05-nh-12-attention-word-design.md` (holds the rules).

**Constraints:** `NoHandsCore` stays pure. A spoken "stop" is never merged and always halts the task, with or without the word. Never edit `scripts/intent-eval*.json`.

## Tasks

1. **Core.** `AttentionGate` is off when the word is empty, over three words, or a stop phrase. `check` returns addressed (with remainder), word only, not addressed, or off; leading fillers are skipped. `AppConfig.attentionWord` defaults to `""`.
2. **Routing.** In command mode only an addressed remainder is routed. Stop takes today's path. Dictation and sleep are unchanged, except escape phrases and "wake up" also work after the word.
3. **Pipeline.** The gate goes to `ModeMachine`, `MergeBuffer` and `isComplete`. While a task runs, not-addressed utterances are dropped, not held (beyond the spec). The word alone is held for the unfinished window.
4. **Docs.** README config and § Privacy ("There is no wake word."); the non-goal line in the architecture spec.

Verify: build, tests.
