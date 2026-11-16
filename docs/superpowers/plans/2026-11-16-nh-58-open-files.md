# NH-58 Open files, folders and recent documents by voice: Implementation Plan

> **For agentic workers:** use subagent-driven-development or executing-plans, task by task.

**Goal:** Voice phrases and a model action `open_file` that open standard folders, named files and "my last <kind>" through a Spotlight name query, guarded to the home folder and never executables.

**Architecture:** Pure logic (folder table, kinds, ranking, `FileOpenGuard`, `FilePick`, request value types) in `NoHandsCore`; a `FileSource`/opener protocol plus `SpotlightFileSource` in `NoHandsMac`; one executor path serves grammar and model.

**Tech Stack:** Swift 6 strict concurrency, NSMetadataQuery, XCTest/Swift Testing as the repo already uses.

**Spec:** docs/superpowers/specs/2026-11-16-nh-58-open-files-design.md (the spec is the source of truth for phrases, guard rules, pick-wait behaviour, logging)

## Global Constraints

- No `@unchecked Sendable`, no `@preconcurrency`; no AppKit/network in NoHandsCore.
- The model passes words, a kind or a folder key, never a path; decoder rejects `path`/`url` fields, `/ \ ~ :` or control characters in `name`, names over 100 chars, unknown keys, bad mixes.
- Guard rules 1-5 from the spec; refusal strings exactly as in the spec.
- Stop phrases are checked first in the pick wait and never merged.
- Log only spoken phrase + action names (`open file`, `open folder <key>`, `open recent <kind>`, `open file pick <n>`); never hit names or paths.
- Every existing phrase keeps working (`open music`, `open home`, `open the YouTube tab`, `open youtube`, `open chrome and go to youtube`).
- Test lines must not exceed feature lines; one table-driven test per rule (AGENTS.md § Testing).

## Review Focus

Symlink-out and prefix-sibling (`/Users/noah2`), dot components in resolved path, execute bit, deny-listed extension, packages (Keynote ok, .app not), out-of-range pick, stop during pick, attention word during pick, route memory dropping the name words.

## Tasks

1. **Core types and guard.** New `Sources/NoHandsCore/FileOpen.swift`: `StandardFolder` (table + aliases), `FileKind`, `FileRequest` (`.folder/.named/.recent`), ranking, `FileOpenGuard.decide(facts)`, `FilePick.reply`. Add `Action.openFile(FileRequest)`; update `ActionSummary`, `RouteMemory` naming (`open_file` + folder/kind only), `SpokenFreeText`, `PackFile` (rejects), `PipelineText`, any exhaustive switches. Tests: table tests for folders, ranking, guard rules, `FilePick.reply`.
2. **Grammar.** In `CommandGrammar.parsePattern` `open` case, before `parseOpenSite`: folder, `open file`, `the/my <words> <kind>`, `my last <kind>`, trash; pick replies (`<n>`, `number n`, ordinals) are handled by the pipeline, not the grammar. Table test incl. phrases that must not change.
3. **Decoder, schema, prompt.** `open_file` in `IntentSchema` native kinds, field schema, prompt rule, Ollama few-shot turn; `IntentDecoder` validation; two eval fixtures appended to `scripts/intent-eval.json` (never edit existing). Decoder table test.
4. **Mac side.** `Sources/NoHandsMac/FileOpening.swift`: `FileSource` protocol, `SpotlightFileSource` (NSMetadataQuery, home scope, 200 results, 2 s timeout, drop Library/dot), opener (Finder for folders), guard facts reader (realpath, URLResourceValues, UTType, exec bit). `ActionExecutor` runs `.openFile`: zero hits -> failure string, one -> guard + open, several -> pick list. Fake-source test: one opens, several list, zero fails.
5. **Pipeline pick wait + board.** `VoicePipeline`: open pick checked at top of `process` before routing; 30 s deadline; stop/cancel, in range, out of range (retry), pass-through, attention-word drop; closed by task start, pause, sleep, mode switch, `stop()`. Several hits inside a macro or model task fail the step with `several files match: say open file <words>`. Rows shown on the corner panel/board.
6. **Docs.** `docs/voice-commands.md` rows, `docs/privacy.md` bullet, `docs/tasks.md` line on `open_file`.
7. **Verify.** `swift build` clean, `swift test` green, intent fixtures unchanged.
