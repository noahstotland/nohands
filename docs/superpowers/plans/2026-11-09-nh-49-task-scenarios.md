# NH-49 Task Scenario Suite Implementation Plan

**Goal:** `nohands-cli scenarios` runs scripted live task goals and scores each against an independent screen check.

**Architecture:** Pure decoding, validation, checks, verdicts and report in `NoHandsCore/TaskScenario.swift`, table tested. The command in `nohands-cli/Scenarios.swift` reuses `TaskRunner`, `ScreenObserver` and `ActionExecutor` as `task` does.

**Spec:** `docs/superpowers/specs/2026-11-09-nh-49-task-scenarios-design.md`

## Constraints

- Tests need no screen, permission or model.
- `maxSteps` 1 to 30. Start URLs http or https only. Check observer: 300 elements.
- Timeouts: start state 20 s, final check 3 s, polled each 1 s; 2 s between scenarios.
- Exit: 0 all `pass`, 2 otherwise, 1 usage or file error, 130 on a second Ctrl-C.
- Don't touch the task loop, its prompt or `scripts/intent-eval*.json`.

## Review focus

- A `done` task whose screen checks fail scores `false-done`, never `pass`. `ignored` is never success.
- `elementAbsent` without an `elementVisible` is rejected at load (an unread page can't pass).
- A hostile file (a `file:` URL, bad regex, `maxSteps` 0 or 99, duplicate name) fails at load; report cells can't break the table.

## Task 1: Core model

- Start (`app` or `url`); five checks (`windowTitleContains`, `urlMatches`, `elementVisible`, `elementAbsent`, `mediaPlaying`); seven verdicts (`pass`, `false-done`, `unclaimed`, `fail`, `stopped`, `start-failed`, `not-run`).
- Load errors name the scenario. `{run}` (Unix seconds) is replaced in the goal and check strings. A check has exactly one key; `urlMatches` compiles case-insensitive at load. A `url` start holds when host (no `www.`) and path match.
- Tests, one table per rule: file rejections, checks, start state, verdicts, report escaping.

## Task 2: The `scenarios` command

No unit tests.

- Args `[file] [--only name]`, default `scripts/task-scenarios.json`. A file error or an unknown `--only` exits 1.
- Per scenario: start, poll until the start state and `ready` checks hold, else `start-failed`. Run `TaskRunner` with both step caps set to `maxSteps`. Unless stopped, poll up to 3 s for all `success` checks.
- After a `mediaPlaying` scenario, click pause.
- The first Ctrl-C marks that scenario `stopped`, the rest `not-run`, and prints the summary.

## Task 3: Scenario file, README, usage

`scripts/task-scenarios.json` with the spec's six scenarios; for `cookie-banner`, pick and verify one real site with a US consent banner. A test loads the shipped file. README CLI row.

## Task 4: First live run and as-built note

`docs/superpowers/as-built/2026-11-09-task-scenarios.md`.

- Without a Claude key the local model runs; say so and list Claude under Not proven. Never write a key.
- Run once with old browser tabs closed.
- The note has hardware, backend, model, date, the verdict table (no titles or URLs), the cookie-banner site, spec differences, and that a rerun is `start-failed` until cookies clear.
