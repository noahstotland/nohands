# As-built: a task asks the user a question

**Shipped:** in PR #130
**Ticket:** NH-47
**Spec:** [2026-11-15-nh-47-task-asks-question-design.md](../specs/2026-11-15-nh-47-task-asks-question-design.md)

## Differs from the spec

- The spec puts the question and answer in one History intent string. Shipped: `StepRecord` has a `userAnswer` field (the question stays in `intent`), and only the request builder writes `Asked: <question> User answered: <answer>` (answer cut to 200 characters). It also changes the word "answered" to "replied" in every other History intent and failure, so model text cannot pass as the user's words. A review found the string version spoofable.
- "Cut to 80 characters with `…`" is 80 in total: 79 characters and the ellipsis.
- An `ask` does not call `onStep` or add a settle time, since no action ran.
- `AnswerKind` is `public private(set) var awaitedAnswer`; `IntentEval.matches` keeps its old overload beside the new one that takes a status.
