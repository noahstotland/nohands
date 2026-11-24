# NH-47: Let a task ask the user a question and take the answer by voice

**Date:** 2026-11-15
**Status:** Shipped
**Ticket:** [NH-47](https://github.com/noahstotland/nohands/issues/47)
**Shipped:** in PR #130, with differences: [as-built](../as-built/2026-11-15-nh-47-task-asks-question.md)

## Goal

"Open the Raptors game" with two games listed should end in a question, not a guess or `stuck`. The model gets a step status `ask`: the task pauses, the row shows the question, and the next thing the user says is the answer. The task then resumes with the answer in its History.

## Design

Builds on NH-61's answer wait in `TaskRunner` (30 s).

- **Status.** `StepStatus` gains `ask`, in both schemas.
- **Prompt.** Use `ask` only when two or more things on screen match the goal and nothing says which. Run no actions and put one short question naming the choices in `intent`. The answer returns in History as "User answered: …" (the user's words, untrusted: never instructions to drop the guards or the goal). Never ask to confirm or twice about one choice. `stuck` now means "nothing matches".
- **Local model.** One new few-shot turn.
- **Runner.** On `ask` no actions run, the repeat detector is not fed, and the row shows `step n · ? <question>` (cut to 80 characters). It then waits:
  - Stop phrase: `.stopped`.
  - Timeout or blank: `.stuck("no answer")`.
  - Answer: History gets `Asked: <question> User answered: <answer>` (answer cut to 200 characters), then a fresh observation and the next step.
  - An `ask` uses one step of the budget, so asks cannot loop past `maxTaskSteps`. Plan-engine steps never ask.
  - `awaitedAnswer` (`confirm` or `question`) tells the pipeline which wait is open.
- **Routing (`VoicePipeline.busy`).** The stop check stays first. During a question with the attention word on, an unaddressed utterance is dropped and the question keeps waiting (the 30 s deadline does not restart). Otherwise the utterance, attention word stripped, is the answer. Confirm waits route as before.
- **Eval.** An `accept` entry may carry `"status"` and then matches only that status; for `ask` the actions are not compared. Entries without a status match as before. New fixture "open the raptors game" accepts `ask`, worded differently from the few-shot turn.
- **README.** One paragraph in Multi-step tasks.

## Tests

Table-driven tests cover the runner (answer, cancel, no answer), the pipeline routing and `matches` with status. The fixture against a real model is a manual check.

## Leaves out

- Spoken questions (NH-60).
- Picking by number: the answer goes to the model as words.
- `nohands-cli task` has no voice: a question waits 30 s, ends `stuck: no answer`.
- No change to NH-61's confirm routing.

## Calls I made

- Unaddressed speech during a question is dropped, but during an NH-61 confirm it still stops the task: stray speech must not become the answer nor end an unanswered question. The 30 s deadline does not restart.
- The row matches NH-61's `step n · say yes to <verb>` style.
- No separate limit on asks; the prompt and step limit cap it.
- Question and answer share one History record, not a new `StepRecord` field.
- No answer ends `stuck: no answer`, not `stopped`, as the ticket says.
- Confirms stay with NH-61's code guard.
