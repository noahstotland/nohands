# NH-48 follow-up commands: plan

Spec: `docs/superpowers/specs/2026-11-16-nh-48-follow-up-commands-design.md`. Test: `swift test`; typecheck: `swift build`.

1. **Core.** `FollowUp.swift` (`refers`, `memory`), `EarlierTask` in `IntentStep.swift`, `StepRequest.earlier`, `AppConfig.followUpWindowMs` (default 30000, clamp 0...120000, missing key). Tests: `FollowUpTests` (phrase table, window table), `AppConfigTests` row.
2. **Request.** `ClaudeRequestBuilder.userBlocks` writes the `Earlier request:` block before `Goal:` (sanitize/unmarked rules). Test: block present and ordered, marker safe.
3. **Runner.** `TaskRunner.run(goal:mode:earlier:)`: puts `earlier` in every `StepRequest`; skips `PlanGate` for a follow-up; media budget and playbooks use earlier goal too; sets `lastTask` on done/stuck/stopped, clears on ignored/failed. Test in `TaskRunnerTests`.
4. **Pipeline.** `VoicePipeline` keeps `lastTask` + end time; in `runTask` computes `FollowUp.memory` from the phrase; chained goal `<earlier>; then: <new>` kept; cleared on non-follow-up task, mode switch, sleep, backend switch. Grammar commands leave it.
5. **Docs.** `docs/voice-commands.md` row, `docs/tasks.md` paragraph, `docs/configuration.md` key.
6. Verify `swift build`, `swift test`; commit and push.
