# NH-42 plan: close pop-ups until the video plays

Spec: `docs/superpowers/specs/2026-11-05-nh-42-close-popups-until-video-plays-design.md` (approved). Test: `swift test`; typecheck: `swift build`.

1. **Core types and ledger.** `Sources/NoHandsCore/BrowserTabs.swift`: `BrowserTab`, `BrowserWindow`, `TabLedger` (baseline by id and title, task tab, new flags), `TabListing` (numbering, caps, sanitized titles, number to id). Table test for the ledger.
2. **Actions, schema, decoder, guard.** `Action.closeTab/closeWindow/selectTab`; schema kinds `close_tab`, `close_window`, `select_tab` (native kinds, `target_number`); decoder; `ActionSummary`; `TabGuard.blocked`. Table tests for the guard and the decoder.
3. **Prompt and message.** `Tabs:` block in `ClaudeRequestBuilder.userMessage` (replaces the unused `Windows:` line; `ScreenObservation` carries the listing); media-goal rules in the system prompt; untrusted-data note. `MediaGoal.matches`, `maxMediaTaskSteps` (default 24, clamp 1...30) in `AppConfig`. Tests: message, config, media goal.
4. **Mac.** `ElementProviding.browserWindows()` (AX tab group read, per-task token registry), executor routes for the three actions, `TaskRunner` wiring (ledger, task-tab marking after open_url/search/searchSite, guard, media step cap). Update fakes. Runner test with a fake browser: pop-under listed new and closed; pre-existing tab blocked.
5. **README** one-liner on ad blockers plus `maxMediaTaskSteps`; run `scripts/intent-eval` fixtures only if a key is available (skip otherwise and say so).

If NH-43 (media signal) or NH-37 (prompt caching) lands on main first, rebase and keep their prompt/message changes.
