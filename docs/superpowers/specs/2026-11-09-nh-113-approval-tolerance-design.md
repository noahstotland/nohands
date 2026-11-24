# NH-113: Set approval risk tolerance to permissive

**Date:** 2026-11-09
**Status:** Shipped
**Shipped:** in PR #115, as specified
**Ticket:** [NH-113](https://github.com/noahstotland/nohands/issues/113)

## Goal

Add the `Approval risk tolerance` row to `docs/agents/project.md`, set to `permissive`, so the team takes Low and Medium risk spec and merge approvals without asking the user. High risk still waits for the user.

## Today

- With no row, `approval_setting()` returns `strict` and every spec and merge asks.
- The setting is read from `project.md` on `origin/main`, so the row takes effect only after the merge.
- The parser takes the first backticked token of the Value cell. A missing row, unknown value or failed read gives `strict`.

## What `permissive` allows

- Low and Medium risk are approved automatically; High still asks. Under `strict` all three ask.
- Reviews, CI and merge checks are unchanged.
- The user is still asked, even under `permissive`, for a change to a file on the approval path (`scripts/`, `docs/agents/`, dot-files, `AGENTS.md`, `CLAUDE.md`), a merge whose PR renames a file, and a ticket the Chief of Staff filed from its own observation.
- A No Hands run keeps its own rules.
- Going back is one edit to `balanced` or `strict`, which also needs the user's approval.

## Design

Add one line to the Identity table, between the `Approver` and `No Hands` rows, in the template's wording with only the value changed:

```
| Approval risk tolerance (`strict`, `balanced` or `permissive`) | `permissive`. Which approvals the team takes without asking: `strict` none, `balanced` Low risk only, `permissive` Low and Medium. High always waits for you |
```

## Non-goals

The other template rows missing from `project.md`; any script, skill or `No Hands` cap.

## Acceptance

- The `project.md` diff is exactly the one added line.
- Before merge: `project_config.value("Approval risk tolerance", rows)` on the branch gives `permissive`.
- After merge: `project_config.approval_setting()` prints `('permissive', '')`. It can't run earlier, so the PR lists it under Not proven.

## Calls I made

- The user's approval is still needed for this spec and its merge: `project.md` is on the approval path.
- "High always waits for you" stays though a No Hands run auto-approves High for its own tickets; it matches the template.
- No plan and no new tests: the change is markdown, and the parser's tests live in collective-wisdom.
