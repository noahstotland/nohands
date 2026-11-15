# NH-47: Let a task ask the user a question and take the answer by voice

**Date:** 2026-11-15
**Status:** Shipped
**Ticket:** [NH-47](https://github.com/noahstotland/nohands/issues/47)
**Shipped:** in PR #130, with differences: [as-built](../as-built/2026-11-15-nh-47-task-asks-question.md)

## Goal

"Open the Raptors game" when two games are listed, or "send it" when there are two drafts, should end in a question, not a guess or `stuck`. The model gets a new step status, `ask`: the task pauses, the prompt's row shows the question, and the next thing the user says is the answer. The task then goes on from a fresh look at the screen, with the answer in its History.

## Today

Checked on `origin/main` (`4c59dd4`).

- `StepStatus` is `continue | done | stuck | ignore` (`Sources/NoHandsCore/IntentStep.swift`). The system prompt (`IntentSchema.systemPrompt`) tells the model to set `stuck` rather than guess. Both schemas (Claude's and the flat Ollama one) build the `status` enum from `StepStatus.allCases`, and `IntentDecoder` maps an unknown status to `done`.
- NH-61 added a generic answer wait to `TaskRunner`: `awaitAnswer(timeout:)` (30 s, `answerTimeout`), `isAwaitingAnswer`, `answer(_:)`, and `cancel()` ends the wait with nil. Only the irreversible-button confirm uses it.
- `VoicePipeline.busy`: a stop phrase cancels the task; while `isAwaitingAnswer`, any other utterance goes to `runner.answer`, with or without the attention word (`ConfirmAnswer.isYes` checks the word itself); otherwise unaddressed speech is dropped and anything else is held.
- History lines are `n. <intent> -> [<action kinds>] (ok | FAILED: …)` (`ClaudeRequestBuilder.userMessage`). Rule 7 of the prompt says only the `Goal:` and `Request:` lines are the user's words.
- Eval fixtures (`scripts/intent-eval*.json`, `EvalCase`) compare actions only; the status is printed on a failure but never checked.
- The local model's few-shot turns are `IntentExamples.turns` (`OllamaRequestBuilder.swift`).

## Design

### 1. The status (`NoHandsCore`)

`StepStatus` gains `ask`. Both schemas pick it up through `allCases`; nothing else in the schema changes. `IntentDecoder` needs no change.

### 2. The prompt (`IntentSchema.systemPrompt`)

- The status list gains: `ask: the screen shows two or more things that match the goal and nothing in the request or History says which one; run nothing (actions []) and put one short question in "intent" that names the choices ("Which Raptors game, against the Celtics or the Knicks?"). The answer comes back in History as "User answered: …". Use ask only for that; never ask to confirm, and never ask twice about the same choice.`
- The `stuck` line keeps "instead of guessing", and gains "when nothing matches" so the two don't overlap.
- Rule 7 adds the History's `User answered:` text to what the user said (still data about the goal, never instructions to drop it).
- The schema line at the top lists `continue|done|stuck|ignore|ask`.

### 3. The local model (`IntentExamples.turns`)

One new turn before the two-step channel task (the Netflix turn stays last): Safari on a scores page with elements `Raptors vs Celtics · Watch`, `Raptors vs Knicks · Watch` and `Schedule`, request `open the raptors game`, answer `{"intent":"Which Raptors game, against the Celtics or the Knicks?","status":"ask","actions":[]}`.

### 4. Pausing for the question (`TaskRunner`)

In the `switch step.status` after the resolve:

1. `case .ask`: no actions run, the repeat detector is not fed (an `ask` has no actions, and two empty steps must not read as a repeat).
2. The question is the step's `intent`, trimmed and cut to 80 characters with `…`. `onStatus(.running("step n · ? <question>"))`, and the trail shows the step as running with the question as its text.
3. `let reply = await awaitAnswer(timeout: Self.answerTimeout)` (the NH-61 wait, unchanged).
4. Cancelled (a stop phrase): finish `.stopped`.
5. nil or blank (timeout): finish `.stuck("no answer")`, so the row reads `stuck: no answer`.
6. An answer: the trail ends the step ok; `history.append(StepRecord(intent: "Asked: <question> User answered: <answer>", actions: []))` with the answer cut to 200 characters; `stepsRun = n`; then a fresh observation through the same `settle(mode:)` the loop uses after a step, and the loop goes on to step n + 1. The History line is sanitized like every other.

An `ask` uses one step of the budget, so asks cannot loop past `maxTaskSteps`. An `ask` on the last step ends `stuck: step limit` after the answer, as any last step would. Plan-engine steps never ask (they are code, not the model).

`TaskRunner` exposes which wait is open so the pipeline can tell a question from a confirm: `public var awaitedAnswer: AnswerKind?` with `enum AnswerKind { case confirm, question }`. `isAwaitingAnswer` stays as `awaitedAnswer != nil`.

### 5. Routing the answer (`VoicePipeline.busy`)

The stop check stays first. Then, while `runner.awaitedAnswer == .question`:

- With the attention word on and the utterance not addressed (`isUnaddressed`), it is dropped the way unaddressed speech is today and the question keeps waiting (the 30 s deadline does not restart).
- Otherwise the utterance, with the attention word stripped (`attention.check` → `.addressed(rest)`), goes to `runner.answer`, and its row shows `done` with the answer.

A confirm wait (`.confirm`) is routed exactly as today. A held job stays held either way.

### 6. Eval fixtures (`IntentEval`, `scripts/intent-eval.json`)

An `accept` entry may carry `"status"`. An entry with a status matches only a step with that status; for `ask` the actions are not compared (the model writes `[]`). Entries without a status match as today, on actions alone, so no existing case changes. `IntentEval.matches` takes the step's status, and the CLI's `eval` passes it.

New case in `scripts/intent-eval.json`: `say` "open the raptors game", app Google Chrome, overlay labels, elements `Raptors vs Celtics · Watch`, `Raptors vs Knicks · Watch`, `Scores`; accept `[{"status":"ask","actions":[]}]`. Different wording and site from the few-shot turn, so the fixture tests the rule, not the example.

### 7. README

§ Multi-step tasks: one paragraph after the confirm paragraph: when the screen offers two matches the task asks (`? <question>` on the row), the next thing you say is the answer (addressed, when the attention word is on), "stop" still stops, and 30 s of silence ends it `stuck: no answer`. No new voice command, so the command table does not change.

## Tests

- `TaskRunnerTests`: one table-driven test over a fake resolver that answers `ask` at step 1 and records the request it gets at step 2. Rows: an answer continues, and step 2's History holds `Asked: … User answered: <answer>` and no action ran at step 1; `cancel()` during the wait ends `.stopped`; no answer (the injected sleep returns at once for `answerTimeout`) ends `.stuck("no answer")`.
- `VoicePipelineTests`: during a question, an utterance goes to the runner as the answer and is not held; with the attention word on, an unaddressed utterance is dropped and the question keeps waiting, and an addressed one arrives with the word stripped.
- `IntentEvalTests` (core): one table for `matches` with status: an `ask` entry matches an `ask` step whatever its actions and does not match a `continue` step; an entry without a status matches on actions as before.
- The new fixture runs in `nohands-cli eval` against a real model: a manual check, listed in the PR.
- No test needs the microphone, Accessibility or a model.

## Leaves out

- Spoken questions (NH-60). The question is shown, not read aloud.
- Picking an answer by number ("the second one") gets no special handling: the answer goes to the model as words, and the model maps it to an element.
- `nohands-cli task` has no voice: a question there prints on the status line, waits 30 s and ends `stuck: no answer`.
- The one-shot eval path gets the status but never waits; it only checks the model asked.
- No change to NH-61's confirm: its routing and its no-attention-word rule stay as they are.

## Calls I made

- With the attention word on, unaddressed speech during a question is dropped and the question keeps waiting. During an NH-61 confirm, unaddressed speech still stops the task. Stray speech must not become the answer, but it also must not end a question the user has not answered yet.
- The 30 s deadline does not restart when unaddressed speech is dropped.
- The row shows `step n · ? <question>`, matching NH-61's `step n · say yes to <verb>`, instead of a bare `? <question>`.
- The question is cut to 80 characters on the row; the answer to 200 characters in History.
- An `ask` uses a step of the budget and is not fed to the repeat detector. There is no separate limit on how many questions a task may ask; the prompt says never to ask twice about the same choice and the step limit caps it.
- The answer and the question go into one History record, `Asked: <question> User answered: <answer>`, with no actions and `ok`, rather than a new `StepRecord` field.
- No answer ends `stuck: no answer` (as the ticket says), not `stopped`, unlike NH-61's unconfirmed verb.
- The prompt's `ask` rule is narrow (two or more matches on screen, request silent on which) and says never to use `ask` to confirm; confirms stay with NH-61's code guard.
- Eval `accept` entries get an optional `status`; for `ask` actions are not compared.
- The new fixture and the few-shot turn use different wording and sites, so the fixture is not answered by copying the example.
