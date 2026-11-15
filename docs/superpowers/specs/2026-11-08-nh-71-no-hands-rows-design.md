# NH-71: Add the No Hands rows to project.md

**Date:** 2026-11-08
**Status:** Shipped
**Ticket:** [NH-71](https://github.com/noahstotland/nohands/issues/71)
**Shipped:** in PR #72, as specified

## Goal

Add the three No Hands rows to `docs/agents/project.md`, with `No Hands` set to `on`, so the user can start a No Hands run from the Chief of Staff thread. Merging does not start a run.

The setting is read from `project.md` on `origin/main`, so the rows take effect only after the merge. Caps must be positive whole numbers; anything else reads as off.

## What `on` allows

`on` only makes a run possible. A run needs the user's own `no hands` message. During it the Chief of Staff approves specs and merges itself at every risk level until the Backlog is empty or a cap is hit. Reviews, CI and merge gates still run. The user still decides specs and merges that touch the hands path, rename a file, have 100 or more files, or have a migration or `flag:` path, or carry an unreviewed conflict-resolution note. This applies to tickets the run started.

## Design

Add three rows to the Identity table after `Approver`: `No Hands` is `on`, `No Hands ticket cap` is `10`, `No Hands cost cap (USD)` is `200`. No other line changes.

## Acceptance

- The diff is exactly the three added lines, and parsing them gives `on`, `10`, `200`.
- After merge, `no_hands_setting()` run from this repo prints `(True, 10, 200, '')`.

## Calls I made

- **The caps are placeholders**: the template defaults, not the user's choice.
- **The ticket's acceptance command is corrected**: run from `~/.collective-wisdom/scripts/` it reads that repo's own `project.md`.
- **No plan and no tests**: the change is markdown.
- **The user approves the spec and merge**: `project.md` is on the approval and hands paths.
