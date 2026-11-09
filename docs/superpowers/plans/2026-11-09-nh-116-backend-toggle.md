# NH-116: Menu toggle between Claude and the local model: Plan

**Spec:** [2026-11-09-nh-116-backend-toggle-design.md](../specs/2026-11-09-nh-116-backend-toggle-design.md)
**Ticket:** [NH-116](https://github.com/noahstotland/nohands/issues/116)

Test budget (`AGENTS.md` § Testing): one table-driven test per rule; test lines stay under the feature lines. Verification after
every task: `swift build` (Swift 6 strict, no `@unchecked Sendable`, no `@preconcurrency`), then `swift test`.

## Task 1: Config patch and menu logic (NoHandsCore)

Files: `Sources/NoHandsCore/BackendMenu.swift` (new), `Sources/NoHandsCore/ClaudeKeyEntry.swift`, `Tests/NoHandsCoreTests/BackendMenuTests.swift` (new).

- `BackendChoice` (`claude`, `local`), `BackendMenu.merged(existing:choice:)`, `BackendMenu.title(config:)`, `BackendMenu.rows(config:keySavedThisSession:)` as in the spec. Share the parse-and-serialize step with `ClaudeKeyEntry.merged` through one internal helper, without changing `ClaudeKeyEntry`'s behaviour or error type.
- Tests: `merged` table (no file, `{}`, other keys kept with types, value replaced, invalid JSON, `[]`, empty file, loads through `AppConfig.load` to the chosen backend); one table for `title` and `rows` over every `intentBackend` x key x saved-this-session.

## Task 2: Mode-preserving write (NoHandsMac)

Files: `Sources/NoHandsMac/ConfigFile.swift`, `Tests/NoHandsMacTests/ConfigFileTests.swift`.

- `ConfigFile.saveIntentBackend(_:at:)` reusing the folder, read and replace steps of `saveAnthropicKey`. `replaceFile` takes the mode: the existing file's permission bits (from the `fstat` in `readRegularFile`, so return them with the data) via `fchmod` on the temp file before the rename; 600 for a new file. `saveAnthropicKey` keeps forcing 600. Same `SaveError`; nothing from the file in any error.
- One table-driven test in a temp folder: new file 600; 600 and 640 files keep their mode; other keys (an API key) survive; symlinked file and folder refused with the target untouched; invalid JSON left byte for byte; no `.config.json.*` temp left.

## Task 3: Live runner swap (NoHandsMac)

Files: `Sources/NoHandsMac/VoicePipeline.swift`, `Sources/NoHandsMac/OllamaIntentResolver.swift`, `Tests/NoHandsMacTests/VoicePipelineTests.swift`.

- `runner` becomes a `var`; add `pendingRunner`, internal `replaceRunner(_:)` (immediate when `activeTask == nil`, else stored, newest wins) and `applyPendingRunner()` called right after each `runTask` returns inside `startTask`. `startTask` reads `self.runner` for every pending task. Add `switchBackend(config:resolver:observer:)` that builds a `TaskRunner` like `init` (screenshots from the new config's `visionEnabled`) and calls `replaceRunner`.
- `OllamaIntentResolver` logs `ollama: step <n> <ms>ms` after a successful step, with no prompt or transcript text, matching the Claude line.
- One table-driven test with injected runners and fakes: swap when idle reaches the next command; swap from a nil runner starts working; swap during a task leaves that task on its runner, a spoken stop still cancels it, and a held command then goes to the new runner.

## Task 4: Menu and wiring (NoHands app)

Files: `Sources/NoHands/AppDelegate.swift`, `Sources/NoHandsMac/PipelineText.swift` only if a string is needed.

- `backendItem` with a submenu built like `statusBarItem`, directly before `claudeKeyItem`; `refresh()` sets its title and rows from `BackendMenu`; a disabled row has its action removed.
- Track `keySavedThisSession` (set in `setClaudeKey` on success). Keep the task `AXQuery` and `harness` in properties so a switch can build a new `ScreenObserver` with the new cap.
- Share one helper that builds the resolver from `config.effectiveBackend` between `startPipelineIfReady` and a switch.
- Pick handler in the spec's order: no-op if already effective; `saveIntentBackend`, HUD on failure and nothing else changes; set `config.intentBackend`; clear `lastClaudeCheck`; clear `lastWarm` on local; `switchBackend` if a pipeline exists; log `intent backend: <name>`; `refresh()`, `refreshLocalModel()`, HUD. HUD texts from the spec table.
- `warmIfDue` returns early unless the backend is local. Startup race: remember the backend `startPipelineIfReady` built with, and after `pipeline = p` call `switchBackend` if `effectiveBackend` differs. Log the backend name at pipeline start.
- No unit test (menu layout and a running model are manual checks listed in the PR).

## Task 5: Docs

- `README.md`: "Backend choice" bullet and § Configuration describe the Model submenu, no restart, other keys kept and file rewritten sorted and indented, `auto` and `off` file-only; "Changes apply after a restart" gets the exception.
- Search the README for other text that says the backend changes only after a restart or in the file only, and fix it.

## Done when

`swift build` and `swift test` are green, `.build/debug/nohands-cli eval scripts/intent-eval.json` is unaffected (no prompt change), and the spec's manual checks are listed for the PR.
