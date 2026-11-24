# NH-61 plan: confirm before irreversible actions

Spec: `docs/superpowers/specs/2026-11-15-nh-61-confirm-irreversible-design.md`. Tests: `AGENTS.md` § Testing (table-driven, test lines <= feature lines). Command: `swift build && swift test`.

1. **Core matcher** (`Sources/NoHandsCore/IrreversibleGuard.swift`): `IrreversibleGuard.held(_:labels:goal:) -> String?` and `ConfirmAnswer.isYes(_:)` per spec §1-2. Reuse `CommandGrammar.normalize`. Test: `Tests/NoHandsCoreTests/IrreversibleGuardTests.swift`, one table for the matcher, one for yes words.
2. **TaskRunner wait** (`Sources/NoHandsMac/TaskRunner.swift`): generic answer wait (`isAwaitingAnswer`, `answer(_:)`, 30 s `answerTimeout` via injected `sleep`, resumed by `cancel()`), called after the existing guard chain; yes runs the step, anything else ends `.stopped` with `stopped: <verb> not confirmed`. Test: one table-driven test in `Tests/NoHandsMacTests/TaskRunnerTests.swift` (yes, no, timeout, cancel, goal already says the verb).
3. **Pipeline routing** (`Sources/NoHandsMac/VoicePipeline.swift` `busy`): after the stop check, route to `runner.answer` while `isAwaitingAnswer`; held job stays held. No new test (needs the pipeline), listed as a manual check in the PR.
4. **README** § Multi-step tasks: paragraph per spec §5.
