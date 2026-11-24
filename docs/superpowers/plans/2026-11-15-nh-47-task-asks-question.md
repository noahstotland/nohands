# NH-47 plan: a task asks the user a question

Spec: [design](../specs/2026-11-15-nh-47-task-asks-question-design.md). Test command: `swift test`; typecheck: `swift build`.

## Tasks

1. **Core status and prompt.** Add `ask` to `StepStatus`; update `IntentSchema.systemPrompt` (status list, schema line, `stuck` line, rule 7); add the `ask` turn to `IntentExamples.turns` before the Netflix turn. Check `swift test` still passes (prompt snapshot tests, if any, are updated for the new text only).
2. **Eval status.** Optional `status` on `accept` entries in `EvalCase`; `IntentEval.matches` takes the step status (ask entries ignore actions); CLI `eval` passes it. New fixture in `scripts/intent-eval.json`. Table test `IntentEvalTests`.
3. **TaskRunner.** `AnswerKind` and `awaitedAnswer`; `case .ask` per spec § 4 (question cut to 80, answer to 200, History record, no repeat-detector feed, fresh `settle`, `stuck("no answer")` on timeout). Table test in `TaskRunnerTests`.
4. **VoicePipeline routing.** Spec § 5: question waits drop unaddressed speech when the attention word is on, strip the word from an addressed answer. Test in `VoicePipelineTests`.
5. **README** paragraph (spec § 7).
