# NH-113: Set approval risk tolerance to permissive

**Date:** 2026-11-09
**Status:** Shipped
**Shipped:** in PR #115, as specified
**Ticket:** [NH-113](https://github.com/noahstotland/nohands/issues/113)

## Goal

Add the `Approval risk tolerance` row to `docs/agents/project.md`, set to `permissive`, so the team takes Low and Medium risk spec and merge approvals without asking the user. High risk still waits for the user.

## Today

Checked 2026-11-09 on `origin/main` (`f58587c`) with the installed collective-wisdom scripts.

- From this repo, `project_config.approval_setting()` returns `('strict', 'no Approval risk tolerance value on the merge target branch')`. The Identity table has no such row, so every spec and merge asks the user.
- The setting is read from `project.md` as committed on `origin/main`, never from a working tree, and read again at each decision. The row takes effect only after the merge.
- The parser takes the first backticked token of the Value cell. A missing row, an unknown value or a failed read gives `strict`.
- The template row is in `~/.collective-wisdom/templates/project.md`, directly after `Approver`.

## What `permissive` allows

`approval_policy.decide` gives this table:

| Risk | `strict` (today) | `permissive` (after this) |
|---|---|---|
| Low | asks | auto |
| Medium | asks | auto |
| High | asks | asks |

The setting doesn't change any gate. Reviews, CI and merge checks run the same at every level. The user is still asked, under `permissive`, for:

- a spec or merge that changes a file on the approval path (`scripts/`, `docs/agents/`, dot-files and dot-directories, `AGENTS.md`, `CLAUDE.md` and the others that `approval_policy.py` lists),
- a merge whose PR renames a file,
- a ticket the Chief of Staff filed from its own observation.

A No Hands run doesn't use this setting. It keeps its own rules, in which High is auto-approved for tickets the run started.

Going back is one edit: set the value to `balanced` or `strict`. That edit is on the approval path, so it needs the user's approval too.

## Design

Add this one line to the Identity table, between the `Approver` and `No Hands` rows, in the template's wording. Only the value differs from the template.

```
| Approval risk tolerance (`strict`, `balanced` or `permissive`) | `permissive`. Which approvals the team takes without asking: `strict` none, `balanced` Low risk only, `permissive` Low and Medium. High always waits for you |
```

No other line of `project.md` changes, and no other file changes except this spec and its closeout.

## Non-goals

- Adding the other template rows missing from `project.md` (`Review after conflict resolution`, `Merge target branch`, `Require teammate approval`).
- Changing `No Hands`, its caps, or any script or skill.

## Acceptance

- The diff of `project.md` is exactly the one added line.
- Before merge: `project_config._parse` on the branch's file, read with `project_config.value("Approval risk tolerance", rows)`, gives `permissive`. A dry run of the exact row against `origin/main` already gives that, and `No Hands` still reads `on`.
- After merge, run from a NoHands checkout, not from `~/.collective-wisdom/scripts/`:

  ```bash
  python3 -I -c "import os, sys; sys.path.insert(0, os.path.expanduser('~/.collective-wisdom/scripts')); import project_config; print(project_config.approval_setting())"
  ```

  It prints `('permissive', '')`.

The post-merge check can't run before the merge, because the setting is read from `origin/main`. The PR lists it under Not proven.

## Calls I made

- **The user's approval is still needed for this spec and its merge.** `docs/agents/project.md` is on the approval path, and this ticket's merge also can't be covered by the auto-approval it turns on. The ticket quotes the user asking for this. That quote is the reason for the ticket, and it isn't an approval of it.
- **"Low or Medium is approved without asking" has exceptions the ticket doesn't list.** The approval-path, rename and observation-ticket cases above still ask. This is existing behaviour and this ticket doesn't change it.
- **The row's wording "High always waits for you" is kept, though a No Hands run auto-approves High for its own tickets.** The ticket gives this exact text and it matches the template. `No Hands` is `on` in this repo, so the sentence is true only outside a run. Fixing it belongs in the template, in collective-wisdom.
- **No plan and no new tests.** The change is markdown only, so ship-loop skips the plan. The parser's tests live in collective-wisdom, and `AGENTS.md` § Testing says not to test constants.
