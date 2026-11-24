# NH-116: Menu toggle between Claude and the local model: Plan

**Spec:** [2026-11-09-nh-116-backend-toggle-design.md](../specs/2026-11-09-nh-116-backend-toggle-design.md)
**Ticket:** [NH-116](https://github.com/noahstotland/nohands/issues/116)

Build and test after every task. One table-driven test per rule.

1. **Patch and menu logic (Core).** `BackendMenu` (`merged`, `title`, `rows`), sharing the parse-and-serialize step with `ClaudeKeyEntry.merged`.
2. **Mode-preserving write (Mac).** `ConfigFile.saveIntentBackend`; the replace step takes the mode (existing bits, 600 for new); the key save keeps 600.
3. **Live runner swap (Mac).** `runner` becomes a `var`; a pending runner is applied after each task returns; `switchBackend`; `ollama: step` log line.
4. **Menu and wiring (app).** `Model` submenu, pick handler in the spec's order, `warmIfDue` local-only, startup race fix. Manual checks only.
5. **Docs.** README Backend choice and Configuration.

Done when build and tests are green, the intent fixtures are unaffected, and the manual checks are listed in the PR.
