# NH-111 View Logs: Plan

Spec: `docs/superpowers/specs/2026-11-15-nh-111-view-logs-design.md` (approved). Test: `swift test`; typecheck: `swift build`.
Tests follow AGENTS.md § Testing: table-driven, none for window/menu/file write, test lines <= feature lines.

1. **Step timing (core).** `TaskStepRecord` gains `startedAt: Date?`, `duration: Duration?`; `TaskTrail.begin/end` take `at: Date = Date()`. End twice keeps first duration. Test in `Tests/NoHandsCoreTests`.
2. **Record + rules (core).** New `Sources/NoHandsCore/CommandLog.swift`: `CommandLogEntry` (+ Step, Outcome, Usage, Resolver), `CommandLog` (limit 50, newest first, `append`, `encoded`, `decode(Data?)` -> empty on any bad input, trims to 50), `fromTrail`, `Usage.sum`, `CommandLogText` (menu line, detail text). Tests: keep-last-50, decode table, entry-from-trail, text rendering.
3. **Usage plumbing (mac).** `IntentResolving.takeUsage() async -> [ClaudeUsage]` (default `[]`); `ClaudeIntentResolver` records usage from `resolve` and `plan`; cleared at task start in `runTask`.
4. **Store (mac).** `CommandLogStore` (`@MainActor`): file `~/.config/nohands/command-log.json`, dir 0700, file 0600, atomic no-follow write like `ConfigFile`; load once; append then write off the main actor, never awaited; write errors -> `PipelineLog.warning`; change callback.
5. **Pipeline feed (mac).** `VoicePipeline` gets the store and a `resolverKind`; record entries per the spec table in `process` (execute/reject/no-resolver) and `runTask`. Stop/ignored/answers/dropped/dictation not recorded. Timing for grammar steps from start/end of execute.
6. **UI (app).** `AppDelegate`: "Recent commands" submenu (rebuilt in `menuWillOpen`, "No commands yet" disabled item), "View Logs…" item; `LogWindowController` (NoHandsMac or NoHands): NSWindow, list left, read-only detail right, live updates, activates app; submenu click opens window at that entry.
7. **Docs.** README: menu items and log file under Configuration.
8. Run `swift build`, `swift test`, intent fixtures untouched.
