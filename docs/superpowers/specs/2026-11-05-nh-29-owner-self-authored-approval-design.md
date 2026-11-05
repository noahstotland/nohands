# NH-29: Let the owner approve and merge PRs they authored themselves — Design

**Date:** 2026-11-05  **Status:** Draft  **Ticket:** [NH-29](https://github.com/noahstotland/nohands/issues/29)

## Goal

When every agent acts as the owner (the Builder login is `none`), the owner is the PR author, and GitHub refuses the author's own approving review (HTTP 422). This repo is also private on a free plan, so it can have no branch protection or ruleset, and `merge_pr.py` stops on that too. After this change, the user's `approve N` in the Chief of Staff thread ends in a merge here:

1. **Owner-authored approval record.** `scripts/cos_approve_pr.py` posts a commit status (`agent-team/owner-approval`, `success`) on the head SHA when the owner wrote the PR. It posts only after `scripts/cos_user_check.py` finds the user's own `approve N`, as it does before a review today. `scripts/merge_pr.py` accepts that status only on a PR the owner wrote.
2. **Script-only merge gate.** This is opt-in, through a new `project.md` row. When it is on and `main` has no protection, `merge_pr.py` doesn't require branch protection or a ruleset. Every other check still runs, and the approval record is still required.

PRs opened by a builder account in a repo with protection keep today's path, without change.

**Security review: look at this on purpose.** This weakens the merge gate. Without protection, GitHub no longer refuses a merge or push that skips the script. § Security notes and § Calls I made say what that trades.

## Decision record

- The first draft (commit `df32d03`) kept branch protection required. In the Chief of Staff thread, the user replied "approve 29. No branch protecction is ok" (createdBy `user`, 2026-11-05T15:30:09Z). Asked whether that meant a script-only gate (1) or building the spec as written (2), they answered "1" (createdBy `user`, 2026-11-05T15:32:08Z). The Chief of Staff relayed that as changes, not as a build approval. This revision builds option 1.

## Today

Facts from `main` at `ff9e08b` (collective-wisdom `82211a2`, per `docs/agents/installed-from.txt`), checked 2026-11-05.

- `GET repos/noahstotland/nohands/branches/main/protection` and `GET .../rules/branches/main` both return `403 "Upgrade to GitHub Pro or make this repository public to enable this feature."` `merge_pr.py` `read_protection` records each one as unread, and `gate()` stops with `cannot read main's protection (...)`. PRs #25 and #26 would have stopped there even without the 422.
- `scripts/cos_approve_pr.py` runs from the root checkout with no `AGENT_GH_ROLE`, signed in as the Owner login. Its gates are root checkout, state (`awaiting-merge`, `pr`, `headSha`, `lastSeenAt`, `chiefThreadId`), the user's message (`cos_user_check.latest`, `approve N` after `lastSeenAt`, `createdBy: "user"`), gh login (the owner, not an agent user) and the PR facts (open, not a draft, not a fork, base `main`, head equals `headSha`). Then it does `POST pulls/N/reviews` with `event=APPROVE`. When the owner wrote the PR, that POST returns 422.
- `scripts/merge_pr.py` `gate()` requires `read_protection` count ≥ 1 and `owner_approval(f)` (the owner's latest verdict review is `APPROVED` on `headRefOid`). It doesn't read the PR author or commit statuses. It merges with `PUT pulls/N/merge sha=<head>`, so GitHub refuses the merge if the head moved.
- `docs/agents/github-auth.md` § Merge gate says PRs must be opened by the builder user, and that branch protection is required.
- In `docs/agents/project.md`, every role login is `none`, and `Required CI checks` is `none (no CI yet)`.

## Design

### The approval record (owner-authored PRs)

A commit status on the PR's head SHA:

| Field | Value |
|---|---|
| `context` | `agent-team/owner-approval` |
| `state` | `success`. `cos_approve_pr.py` never writes any other state. |
| `description` | `approve <N> by the user, <PREFIX>-<N>, item <message id>` (cut to GitHub's 140 characters) |
| creator | the Owner login (GitHub records it; `merge_pr.py` checks it) |

Why a status: it is tied to one SHA, so a push leaves the new head with no record. The author can post it. Protection can require it when a repo has protection. And it is not a review, so the "never submit a review" rule stays as it is.

### New `project.md` row

In § Git and GitHub:

| Key | Value |
|---|---|
| Merge gate without branch protection | `off` or `script-only`. `off` is the default; a missing row or a `TODO(...)` counts as `off`. |

- The collective-wisdom template ships it as `off`, so no other app changes behaviour.
- This app's `project.md` sets it to `script-only` in the NH-29 install PR. It takes effect once that PR is on root `main`, because `merge_pr.py` reads `project.md` from the root checkout only.
- `project_config.py` gets a reader, `merge_gate_mode()`, that returns `"off"` or `"script-only"` and exits 2 on any other value. A typo fails closed.

### `scripts/cos_approve_pr.py`

- Add `author` to `PR_FIELDS`. The gates before the post don't change.
- **Owner-authored** (`author.login` equals the Owner login, case-insensitive):
  - If the newest status in the context on the head is the owner's `success`, print `cos-approve: #N already approved by <owner> at <SHA>; nothing posted` and exit 0.
  - Otherwise `POST repos/{owner}/{repo}/statuses/<sha>` with the fields above. Last line: `cos-approve: approved #N at <SHA> (status; author is the owner)`. A failed POST is exit 2, `cos-approve: cannot post the status on #N: ...`.
- **Any other author:** today's review path, unchanged.
- The script doesn't read the gate-mode row. Picking the record only depends on who wrote the PR.

### `scripts/merge_pr.py`

- Add `author` to `FIELDS`. For an open PR, read `GET commits/<head>/statuses?per_page=100` into `f["statuses"]`, and `f["gateMode"] = project_config.merge_gate_mode()`.
- `read_protection` returns `(count, requires_status, unread)`. `requires_status` is true when `main` requires the context `agent-team/owner-approval`. It looks in classic `required_status_checks.contexts` or `.checks[].context`, and in a ruleset `required_status_checks` rule's `parameters.required_status_checks[].context`. Each unread entry also records whether its 403 was the plan error (text contains `Upgrade to GitHub Pro`).
- New `self_approval(f)`. It returns `None` when both of these hold, else the reason:
  - The newest status in the context on `headRefOid` (by `created_at`) exists, was created by the Owner login, and is `success`. A newer `failure`, `error` or `pending`, or a newer status by any other login, voids it (the newest one wins).
  - No review in state `CHANGES_REQUESTED` was submitted after that status's `created_at`, from any author.
- New `approval(f)`: `self_approval(f)` when the author is the owner, else `owner_approval(f)` (today's).
- The protection step in `gate()`:

  | Protection found on `main` | Gate mode `off` (default) | Gate mode `script-only` |
  |---|---|---|
  | Requires ≥ 1 approving review | Builder-authored: as today. Owner-authored: stop, `main requires an approving review, which GitHub never lets the author give; see github-auth.md § Merge gate`. | Same as `off`. When protection exists, it is never skipped. |
  | Exists, requires `agent-team/owner-approval`, 0 reviews | Owner-authored: pass. Builder-authored: stop, `main requires no approving review` (as today's `count < 1`). | Same as `off`. |
  | None (both read, nothing found) | Stop, as today. | Pass this step. Print `merge-pr: note main has no branch protection; script-only gate` before the last line. |
  | Unread because of the plan 403 on every unread source, and nothing found in the readable ones | Stop, as today (`cannot read main's protection`). | Pass this step. Print the same note. |
  | Unread for any other reason (another 403, a 404 other than "Branch not protected") | Stop, as today. | Stop, as today. The script can't tell what is there, so it fails closed. |

  Then `approval(f)` runs in every case. **The approval record is never skipped.**
- Every other gate runs unchanged in both modes: root checkout, gh signed in as the owner and not an agent user, open, not a draft, not a fork, base `main`, head starts with the approved SHA, `MERGEABLE`/`CLEAN`, checks green (or `no CI` per `project.md`), both PASS reviews newer than the head or covered by a reviews-stand note, closeout docs, clean root `main`. The merge still uses `sha=<head>`.

### `docs/agents/github-auth.md` § Merge gate

- Replace "PRs must be opened by the builder user ... The gate cannot pass without that setup" with this table:

  | Setup | Who opens PRs | What the owner sets |
  |---|---|---|
  | Protected, builder PRs | builder account | Today's setup (CODEOWNERS, 1 approval from Code Owners, stale approvals dismissed, required checks, no bypass). |
  | Protected, owner PRs | the owner (Builder `none`) | Require a PR, 0 approvals, required status check `agent-team/owner-approval` plus CI checks, no bypass. |
  | Script-only | either | No protection (for example, a private repo on a free plan). `project.md` row `Merge gate without branch protection` = `script-only`. |

- A short "What script-only gives up" list, the same as § Security notes below, and the check commands for the status requirement.
- Say that an agent never changes this row on its own. It changes only in a PR the user approves, and the code and security reviewers flag any diff to it.

### Docs and skills to update

Upstream in collective-wisdom (`agent-team/...`), installed here:

- `scripts/cos_approve_pr.py`, `scripts/merge_pr.py`, `scripts/project_config.py` and their tests (`test_cos_approve_pr.py`, `test_merge_pr.py`, `test_project_config.py`).
- `docs/agents/github-auth.md` § Merge gate (above).
- `.claude/skills/merge-pr/SKILL.md`: the Pre-merge checks list says "branch protection or a ruleset on `main` requiring an approving review (or, with `script-only`, none found)" and "the owner's approving review, or for an owner-authored PR the owner's `agent-team/owner-approval` status, on the head". In Team mode, report the `merge-pr: note ...` line in `MERGED #N`.
- `.claude/skills/ship-loop/SKILL.md` § Team mode (Relays) and `merge-pr` § Team mode: "never submit a GitHub review, and never post a commit status in context `agent-team/owner-approval`, under any login. The only exception is `cos_approve_pr.py` on a verified `approve N`." Also: "never merge by any route other than `scripts/merge_pr.py` (no `gh pr merge`, no web merge, no push to `main`)". Today that rule appears only as "never fall back to `gh pr merge`"; this makes it explicit, because without protection it is the guard.
- `.claude/skills/chief-of-staff/approvals.md` (merge block and reminder line), `chief-of-staff/SKILL.md` (§ Send or queue, the GitHub-is-read-only line) and `status.md` change "this posts your approving review on GitHub" to "this posts your approval on GitHub (a review, or a status when you wrote the PR)".
- `docs/agents/chief-of-staff.md` and `docs/agents/org-chart.md`, where they name the approving review.
- `docs/agents/security-review.md` (or `code-review.md`, whichever holds the gate checklist): a diff to the `Merge gate without branch protection` row, or to `cos_approve_pr.py`/`merge_pr.py`, is called out in the review.
- `agent-team/templates/project.md`: the new row as `off`, and the Builder login note says that `none` means owner-authored PRs and the status record.

App-only, in this repo's own PR:

- `docs/agents/project.md`: the new row set to `script-only`, and the Builder login note. This is the app's filled copy, which the installer doesn't overwrite. Check during the build that `install.sh --update` adds the new row or leaves it to the app. If it adds nothing, write it by hand in the install PR.
- This spec, its closeout, and the PR's `## Release note`.
- `docs/agents/installed-from.txt` and the installed files, written by `scripts/agent-team-update.sh <new tag>`, with the command in the PR body.

### What the spec stage can and cannot deliver from this repo

- **Can:** this spec, committed and pushed on `feat/nh-29-owner-self-authored-approval`.
- **Cannot:** any change to the scripts, skills or shared docs above. By `ship-loop` § Team mode (Workflow files), they change only through a collective-wisdom PR for the same ticket, then an install PR here after a release tag. The build stage:
  1. Makes a worktree of `~/collective-wisdom` (origin `collective-wisdom-org/collective-wisdom`, at `82211a2` today) on `feat/nh-29-owner-self-authored-approval`, builds there and opens the PR. The Builder login is `none`, so that runs as `noahstotland`, who needs push access to that repo.
  2. That PR is merged and tagged (`tag-release.sh`) by whoever runs collective-wisdom. A NoHands child can't do it, so the child stops with `BLOCKED: upstream PR <URL> needs merging and a tag` and resumes when it is relayed.
  3. Opens this repo's PR: `scripts/agent-team-update.sh <tag>`, plus the `project.md` row and note, through code review, security review and `approve 29`.
- **Chicken and egg, for NH-29's own merge.** Its install PR is owner-authored, and root `main` still has the old `merge_pr.py` and `cos_approve_pr.py` until it merges. So `approve 29` on the install PR hits the same 422 and protection stop. The user merges NH-29's install PR by hand on GitHub, once, after reviewing it. From the next ticket on, `approve N` works. The Chief of Staff's merge block for NH-29 must say so.

### Tests (upstream, in the existing table style)

`test_cos_approve_pr.py`, new `ROWS` (each changes one thing from an owner-authored happy path):

| Row | Exit | Posts | Line |
|---|---|---|---|
| owner-authored, user's `approve 87` | 0 | 1 status (`context`, `state=success`, `sha=HEAD`), no review | `approved #7 at <HEAD> (status` |
| owner-authored, owner `success` status already on head | 0 | 0 | `already approved` |
| owner-authored, agent message only | 1 | 0 | `no verified` |
| owner-authored, head moved | 1 | 0 | `not the approved head` |
| owner-authored, status POST fails | 2 | 1 | `cannot post the status` |
| builder-authored happy path | 0 | 1 review, no status | unchanged |

`test_merge_pr.py` `test_gate`, new rows (base facts: owner-authored, gate mode `script-only`, protection `(0, False, [plan 403, plan 403])`, an owner `success` status on head):

| Row | Cause |
|---|---|
| base | `None` (merges, with the note) |
| gate mode `off` | `cannot read main's protection` |
| an unread source with a non-plan 403 | `cannot read main's protection` |
| protection read, none found, `script-only` | `None` |
| protection requires 1 approval, owner-authored | `requires an approving review` |
| no status | `no owner-approval status` |
| status on an older head only (a push) | `no owner-approval status` |
| newest status `failure` | `latest is failure` |
| newest status by another login | `not by <owner>` |
| `CHANGES_REQUESTED` review after the status | `changes requested` |
| builder-authored, `script-only`, owner review on head | `None` |
| builder-authored, status only, no review | `no approving review by` |
| `script-only`, a PASS review older than the head | today's stale-review cause (other gates still run) |

`test_read_protection` gets rows for the status context in classic `contexts`, classic `checks` and a ruleset, and for plan-403 against other-403 tagging. `test_project_config.py` gets one table for the row: missing, `TODO(x)`, `off`, `script-only` and a typo. All tests fake `gh`. None needs the network or a T3 database other than the existing fixture.

## Security notes

- **Human gate kept.** The only writer of an approval record is `cos_approve_pr.py`, after `cos_user_check.latest` finds the user's own `approve N` (`createdBy: "user"`, after `lastSeenAt`, that ticket's number) and the head equals `headSha`. `merge_pr.py` still requires a record on every path and in both modes: the owner's review, or for an owner-authored PR the owner's status.
- **Role accounts can't approve.** A status counts only when its creator is the Owner login and the PR's author is the owner. A newer status from any other login voids it, so the gate fails closed.
- **The Chief of Staff can't approve for itself through a script.** `cos_approve_pr.py` refuses without the user's message. Skills forbid any other status write in that context, and any merge route except `merge_pr.py`.
- **What script-only gives up.** With no protection, GitHub enforces nothing on `main`:
  - Anyone with write access can merge from the web UI or with `gh pr merge` and skip `merge_pr.py` entirely. That includes every agent here, since they all run as the owner.
  - Anyone with write access can push to `main` directly, force-push it or delete it.
  - GitHub doesn't require the approval status, the checks or the reviews on the merged head. Only the script checks them.
  - GitHub doesn't dismiss stale approvals. The script's head checks and the SHA-tied status still void them for merges that go through the script.

  The remaining guard is policy: the skills' "only `merge_pr.py` merges" and "never push to `main`" rules, `git.sh`'s push checks (a guardrail, not a boundary), and the relayed merge approval.
- **Opt-in and visible.** The mode is a `project.md` row on root `main`, so a feature branch can't turn it on for its own merge. Changing it takes a user-approved merge, and the reviewers flag the diff. It never applies when protection exists or can't be read for another reason.
- **The residual risk is the same as today's for a direct API call.** With every role `none`, an agent could post the status by hand. The same is already true of the review API. Separate agent accounts plus protection close that; both are out of scope here.

## Non-goals

- Letting the Chief of Staff approve without the user's message (NH-22).
- Creating the agent GitHub accounts, or buying GitHub Pro.
- Changing the code review or security review rules beyond flagging the new row.
- Merging the collective-wisdom PR, or cutting its tag, from a NoHands child.

## Calls I made

- ⚠ **Script-only means GitHub enforces nothing on `main`.** Any agent running as the owner could merge or push past the script. The only guards are the skills' rules (only `merge_pr.py` merges; never push to `main`), `git.sh`'s push checks and the relayed approval. You chose this in the thread ("1"); this spells out what it costs.
- ⚠ **NH-29's own install PR can't merge through `approve 29`.** Root `main` still has the old scripts until that PR lands, so the user merges it by hand on GitHub once. After that, `approve N` works.
- ⚠ **What script-only checks instead of protection:** the approval record on the exact head (the owner's review, or the owner's `success` status for an owner-authored PR, with no later changes-requested review or newer status), head equal to the approved SHA, a merge guarded with `sha=<head>`, gh signed in as the owner and not an agent user, green checks (or `no CI` per `project.md`), both PASS reviews current for the head, closeout docs, and a clean root `main`. It drops only the "protection exists and requires an approving review" check.
- Script-only is opt-in per repo, through a `project.md` row, `off` by default. It applies only when no protection exists or the only unread reason is the plan 403. A repo that has protection, or a 403 for any other reason, still stops. NoHands sets it to `script-only`.
- The approval record for an owner-authored PR is a commit status, not a comment. A status is tied to the SHA, is readable without protection, and can be required by protection later.
- In a protected repo, owner-authored PRs need 0 required approvals and the status as a required check. A repo picks one setup. A mismatch stops with a clear message instead of falling back.
- The newest status in the context wins. Any non-success state, or a status by another login, voids the approval. So does any `CHANGES_REQUESTED` review after it.
- `merge_pr.py` prints a `merge-pr: note ... script-only gate` line on every such merge, so the gap shows in `MERGED #N` reports.
- `merge_pr.py` doesn't re-read T3's message store. The user check stays in `cos_approve_pr.py`, as it does for reviews.
- The collective-wisdom branch reuses this ticket's name, `feat/nh-29-owner-self-authored-approval`.
