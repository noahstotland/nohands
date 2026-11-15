# As-built: a task asks the user a question

**Shipped:** in PR #130
**Ticket:** NH-47
**Spec:** [2026-11-15-nh-47-task-asks-question-design.md](../specs/2026-11-15-nh-47-task-asks-question-design.md)

## Differs from the spec

- The spec says the History line is sanitized like every other. History intents are cut to 80 characters, which would drop the user's answer, so a record starting `Asked:` is cut to 320 instead (`ClaudeRequestBuilder`).
- "Cut to 80 characters with `…`" is 80 in total: 79 characters and the ellipsis.
- An `ask` does not call `onStep` or add a settle time, since no action ran.
- `AnswerKind` is `public private(set) var awaitedAnswer`; `IntentEval.matches` keeps its old overload beside the new one that takes a status.
