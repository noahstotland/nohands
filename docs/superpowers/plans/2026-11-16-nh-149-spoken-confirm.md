# NH-149 Spoken yes before irreversible fixed phrases: Implementation Plan

> **For agentic workers:** use subagent-driven-development or executing-plans, task by task.

**Goal:** A fixed phrase marked as needing a confirm is held in the task slot until a spoken yes; packs cannot leave the mark off a phrase that sends or deletes.

**Spec:** docs/superpowers/specs/2026-11-16-nh-149-spoken-confirm-design.md (source of truth)

## Global Constraints

- Swift 6 strict concurrency; no `@unchecked Sendable` (new code), no `@preconcurrency`; no AppKit/network in NoHandsCore.
- "stop" is never merged and always drops a held phrase and halts the task; `busy()`'s stop branch stays first.
- Every existing phrase keeps working. `parse` keeps its signature (callers unchanged); only `routeCommand` and the pipeline learn about the mark.
- Tests: one table-driven test per rule (AGENTS.md § Testing); test lines must not exceed feature lines; no mic, Accessibility or model. Run `swift build` and `swift test`.

## Tasks

1. **Core: the mark.** `AppPack.confirms: Set<String>` (init param default `[]`, normalized keys). `PackSet` carries it per app with the winning pack. `CommandGrammar.confirmed` (global: "empty trash", "empty the trash") and `CommandGrammar.match(_:frontmost:textFocused:) -> GrammarMatch?` (`actions`, `confirm: String?`, `bundleID: String?`); `parse` = `match(...)?.actions`. `Routing.confirm(HeldPhrase)` from `routeCommand` (so `route` and `routeStep` both get it); a hit with `.setMode` is never held. `ConfirmAnswer.timeout = .seconds(30)`; `TaskRunner.answerTimeout` uses it.
2. **Core: mark the built-ins.** Mail send group (+ new bare `send`), Mail delete group, Messages delete conversation group, Chrome `delete browsing data`, Finder move-to-trash group, global `empty trash`. Not marked: `undo send`, `send control c`, `remove breakpoint`. Built-in invariant test: every built-in phrase the forced rule (task 3) catches is marked, minus those three.
3. **Core: pack file.** Optional `"confirm"` bool per command (non-bool: `bad confirm (true or false)`). `PackFile.forcesConfirm(phrase:actions:)`: a phrase's words contain a guarded verb name from `IrreversibleGuard` (whole words; add "trash"; not when the phrase starts with "undo"), or actions equal a marked built-in command's actions for an overlapping bundle ID, or equal another forced command's actions in the same pack. `false` on a forced command: `confirm false on an irreversible command (it names send, delete or another guarded verb)`. Forced with no field: stored as asking. `encode` writes `"confirm": true`. `PackSummary.commandLines` appends ` (asks first)`; `PackDiff` adds `now asks first` / `no longer asks first`. `PackDraft` passes through.
4. **Mac: pipeline.** Injectable `frontmostBundleID` (default NSWorkspace) used for routing, macro steps and the yes check. `PendingTask.confirm`; `process` returns it for `.confirm` (after `canExecute`); `startTask` runs `runConfirm` in the slot: row `.running("say yes to <phrase>")`, `say(.confirm(verb: phrase))`, wait `ConfirmAnswer.timeout` via a pipeline-owned answer channel; `busy()` branch (after stop) hands the utterance over. Yes: pack phrase with changed front app fails `<App> is no longer in front: say it again`; else `executor.execute(actions, files: .spoken)`, command log, done/failed row. Else `.dropped("not confirmed")`; timeout `.dropped("no yes in 30 s")`. `runMacro` `.confirm` case: same wait, failure ends the macro (`not confirmed`). Log each ending.
5. **CLI.** `run` refuses a marked phrase (`asks first: not run from the CLI`); `parse` prints `(asks first)`.
6. **Tests.** Core table tests (grammar routing, built-in invariant, pack file rules, summary/diff). Pipeline tests in `VoicePipelineTests` (yes/confirm/do it/please yes run; yeah, other command, unaddressed, timeout, stop drop; pack front-app change; macro step). Shorten the timeout via an internal var for tests.
7. **Docs.** `docs/voice-commands.md` (asks-first notes, Mail `send` row, paragraph on yes words/30 s/stop), `docs/app-packs.md` (field, forced rules, summary line). Add `**Shipped:**` per closeout in open-pr.
