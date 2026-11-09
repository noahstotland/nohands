# NH-71: Add the No Hands rows to project.md

**Date:** 2026-11-08
**Status:** Draft
**Ticket:** [NH-71](https://github.com/noahstotland/nohands/issues/71)

## Goal

Add the three No Hands rows to `docs/agents/project.md`, with `No Hands` set to `on`, so the user can start a No Hands run in this repo from the Chief of Staff thread. Merging this does not start a run.

## Today

Checked 2026-11-08 on `origin/main` (`4e79d16`) with the installed collective-wisdom scripts.

- From this repo, `project_config.no_hands_setting()` returns `(False, 0, 0, 'no usable No Hands value on the merge target branch')`. `no_hands.py start` refuses on that. The Identity table has no No Hands rows.
- The setting is read from `project.md` as committed on `origin/main`, never from a working tree, so the rows take effect only after the merge.
- The parser wants the first backticked token of the Value cell. `No Hands` must be `on` or `off`. Both caps must be positive whole numbers, digits only. Anything else reads as off.
- The template has the rows at `~/.collective-wisdom/templates/project.md` lines 20-22, with `No Hands` set to `off`.

## What `on` allows

`on` only makes a run possible. A run still needs the user's own message `no hands` in the Chief of Staff thread, and `no_hands.py` re-checks that message, the setting and the spend each time.

During a run, for tickets the run started, the Chief of Staff approves specs and merges itself at every risk level, High included, until the Backlog is empty or a cap is hit. Reviews, CI and merge gates still run. The user still decides specs and merges that touch the hands path, and merges that rename a file, have 100 or more files, have a migration or `flag:` path, or carry an unreviewed conflict resolution.

With no run active, nothing changes. Setting the one value back to `off` turns it off.

## Design

Add these three lines to the Identity table, directly after the `Approver` row, in the template's wording. Only the first value differs from the template.

```
| No Hands (`off` or `on`) | `on`. Whether you may start a No Hands run: the Chief of Staff approves specs and merges itself, at any risk level, until the Backlog is empty or a limit below is hit. Reviews, CI and merge gates still run; changes to the files that decide approvals still wait for you |
| No Hands ticket cap | `10`. Tickets one No Hands run may start |
| No Hands cost cap (USD) | `200`. API-equivalent spend of the run's tickets, from `agent_usage.py` |
```

No other line of `project.md` changes.

## Non-goals

- Changing any gate, invariant or script.
- Changing or adding any other row, including `Approval risk tolerance`.
- Starting a run. That takes the user's `no hands` message after this merges.

## Approaches

- **Three rows from the template, `on` (chosen).** This is what the ticket asks for.
- **Rows with `off`.** Safer to merge, but it needs a second edit to `project.md`, with its own approval, before a run can start. It doesn't meet the ticket.
- **Copy the whole newer template block,** adding the `Approval risk tolerance` and `Review after conflict resolution` rows too. Out of scope, and it would set policy the ticket doesn't mention.

## Acceptance

- The diff of `project.md` is exactly the three added lines.
- Before merge: `project_config._parse` on the branch's file gives `on`, `10` and `200` for the three rows.
- After merge, run from a NoHands checkout, not from `~/.collective-wisdom/scripts/`:

  ```bash
  python3 -I -c "import os, sys; sys.path.insert(0, os.path.expanduser('~/.collective-wisdom/scripts')); import project_config; print(project_config.no_hands_setting())"
  ```

  It prints `(True, 10, 200, '')`.

The post-merge check can't run before the merge, because the setting is read from `origin/main`. The PR lists it under Not proven.

## Calls I made

- **The caps are placeholders.** 10 tickets and $200 per run are the template defaults, which the user didn't choose. Say other numbers at approval and the rows change before the build. Both must be positive whole numbers.
- **The ticket's acceptance command is corrected.** It runs from `~/.collective-wisdom/scripts/`, where git resolves to the collective-wisdom repo and reads that repo's own `project.md`. There it prints `(False, 10, 200, '')` whether or not this ships. The check above runs from this repo.
- **The rows go directly after `Approver`.** The ticket says so. The template has two other rows between them, which this repo doesn't have and this ticket doesn't add. A missing `Approval risk tolerance` reads as `strict`, and a No Hands run doesn't use it.
- **No plan and no new tests.** The change is markdown only, so ship-loop skips the plan. The parser's tests live in collective-wisdom, and `AGENTS.md` § Testing says not to test constants.
- **The user approves this spec and its merge.** `docs/agents/project.md` is on both the approval path and the hands path, so neither can be auto-approved.
