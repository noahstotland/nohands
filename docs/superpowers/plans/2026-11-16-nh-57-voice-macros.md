# NH-57 Voice Macros Implementation Plan

> Spec: `docs/superpowers/specs/2026-11-16-nh-57-voice-macros-design.md`. Follow `AGENTS.md` § Testing: one table-driven test per rule; test lines no more than feature lines.

## Files

- Create `Sources/NoHandsCore/Macros.swift`: `Macro` (name, steps), `Macros` (Codable, Equatable, Sendable; lenient decode like `Vocabulary`; `skipped`; `match(_ transcript:) -> Macro?`). Load rules from the spec; the built-in-phrase check uses `CommandGrammar().parse(name) != nil`, the mode-phrase check `CommandGrammar.isReservedGlobal` (make it `internal`-visible already; it is `static` in core).
- Modify `Sources/NoHandsCore/AppConfig.swift`: `macros` (private(set), default empty), CodingKeys, lenient decode (non-object counts one skipped).
- Modify `Sources/NoHandsCore/ModeMachine.swift`: `Routing.macro(Macro)`; a `macros` value passed to `init`/`use(macros:)`; in `routeCommand`, after the grammar misses and no `rejection`, look the macro up before `.resolveWithLLM`; `routeStep(_:frontmost:textFocused:)` routes one step in command mode with no attention word and no macro lookup.
- Modify `Sources/NoHandsMac/VoicePipeline.swift`: handle `.macro` in `process` (return a new pending kind that `startTask` runs in `activeTask`); the step loop from the spec (row text `step n of m · …`, stop via `canExecute`/cancel, 500 ms pause after a grammar step, model step via `runTask` on the same row with the final line replaced, fail/stuck/ignored end the macro, mode change ends it, LLM off fails at the model step); `isComplete` treats a macro name as complete; command log phrase `name › step`.
- Modify `Sources/NoHands/AppDelegate.swift`: log `macros: skipped N (see docs/configuration.md)` when `skipped > 0`.
- Modify `Sources/NoHandsMac/PipelineText.swift` (and its summary switch) for the new `Routing` case.
- Docs: `docs/configuration.md` (row + bullet), `docs/voice-commands.md` (row), `docs/tasks.md` (one line on follow-ups).
- Tests: `MacrosTests.swift` (match table, load-rules table), `AppConfigTests.swift` (decode), `ModeMachineTests.swift` (routing table), `VoicePipelineTests.swift` (in order, stop ends it, failing step names the step).

## Tasks

1. `Macros` + tests (matching and load rules).
2. Config decode + test.
3. `ModeMachine` routing and `routeStep` + test; fix every `switch` over `Routing`.
4. Pipeline runner for `.macro`; three pipeline tests.
5. AppDelegate log line; docs.
6. `swift build` (clean, strict concurrency) and `swift test` green; commit and push.
