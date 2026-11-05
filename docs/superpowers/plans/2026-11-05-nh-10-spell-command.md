# NH-10: Spell command — Plan

**Spec:** [2026-11-05-nh-10-spell-command-design.md](../specs/2026-11-05-nh-10-spell-command-design.md)

## Tasks

0. Verify: `swift build` and `swift test` (no permissions, no Ollama).
1. `NoHandsCore/Speller.swift`: token table and `Speller.spell`, all-or-nothing.
2. `CommandGrammar`: `spell` case returns `[.typeText]`; `rejection(_:)` gives the HUD line.
3. `ModeMachine`: `Routing.reject`, returned in command mode when the grammar rejects instead of resolving with the model.
4. `NoHandsMac`: `VoicePipeline` reports `.failed(message)`; `isComplete` never completes a `spell` phrase; `PipelineText.summary` keeps the message out of the public log.
5. CLI `parse` prints `rejected: ...`; README table row and CLI example.
6. Tests: `SpellerTests` (tables for tokens, failures, grammar and routing), one `isComplete` line in `MergeBufferTests`.
