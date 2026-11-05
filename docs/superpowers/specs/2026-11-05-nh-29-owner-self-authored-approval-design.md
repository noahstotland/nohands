# NH-29: Let the owner approve and merge PRs they authored themselves — Design

**Date:** 2026-11-05  **Status:** Draft  **Ticket:** [NH-29](https://github.com/noahstotland/nohands/issues/29)

## Goal

When every agent acts as the owner (the Builder login is `none`), the owner is the PR author, and GitHub refuses the author's own approving review (HTTP 422). This spec adds a second approval record that the owner can post on their own PR: a commit status on the head SHA. `scripts/cos_approve_pr.py` posts it only after `scripts/cos_user_check.py` finds the user's own `approve N`, as it does for the review today. `scripts/merge_pr.py` accepts that record only when the PR author is the owner. PRs opened by a builder account keep today's path, the owner's approving review, without change.

**Security review: look at this on purpose.** This adds a second kind of merge approval. § Security notes says what it trades and what it doesn't.

## ⚠ Blocker found while writing the spec: this repo cannot have branch protection

Checked 2026-11-05 as `noahstotland`:

```
GET repos/noahstotland/nohands/branches/main/protection -> 403 "Upgrade to GitHub Pro or make this repository public to enable this feature."
GET repos/noahstotland/nohands/rules/branches/main      -> 403 (same text)
```

`noahstotland/nohands` is a private repo on a free plan, so it can have no classic branch protection and no ruleset. `merge_pr.py` requires one of them (`read_protection`, then the `count < 1` gate), and stops with `cannot read main's protection (...)`. **PRs #25 and #26 would have stopped there even if the 422 had not happened.** This spec doesn't fix that. To meet the ticket's first acceptance line in this repo, the owner has to do one of these:

1. Upgrade the account to GitHub Pro (or make the repo public), then set up `main` as § Branch protection says. **This spec assumes this option.**
2. Ask for a script-only gate for repos that can't have protection (a `project.md` row that lets `merge_pr.py` skip the protection check). That changes a merge gate, so this spec doesn't add it. Reply `changes 29: script-only gate` to get it in a follow-up ticket or in this one.

## Today

Facts from `main` at `ff9e08b` (collective-wisdom `82211a2`, per `docs/agents/installed-from.txt`), checked 2026-11-05.

- `scripts/cos_approve_pr.py` runs from the root checkout with no `AGENT_GH_ROLE`, signed in as the Owner login. Its gates are root checkout, state (`awaiting-merge`, `pr`, `headSha`, `lastSeenAt`, `chiefThreadId`), the user's message (`cos_user_check.latest`, `approve N` after `lastSeenAt`, `createdBy: "user"`), gh login (the owner, not an agent user) and the PR facts (open, not a draft, not a fork, base `main`, head equals `headSha`). Then it does `POST pulls/N/reviews` with `event=APPROVE` and `commit_id=<head>`. When the owner wrote the PR, that POST returns 422.
- `scripts/merge_pr.py` `gate()` requires `read_protection` count ≥ 1 and `owner_approval(f)` (the owner's latest `APPROVED`/`CHANGES_REQUESTED`/`DISMISSED` review is `APPROVED` on `headRefOid`). It doesn't read the PR author or commit statuses.
- `docs/agents/github-auth.md` § Merge gate says PRs must be opened by the builder user, and that the gate can't pass without that setup. Its one-time setup asks for CODEOWNERS plus 1 required approval from Code Owners.
- In `docs/agents/project.md`, the Builder, Chief of Staff and reviewer logins are all `none`, so every PR's author is `noahstotland`, which is also the Owner login.
- `merge-pr` § Team mode, `ship-loop` § Team mode (Relays) and the Chief of Staff docs say: never submit a GitHub review under any login, except through `cos_approve_pr.py`.

## Design

### The approval record

A commit status on the PR's head SHA:

| Field | Value |
|---|---|
| `context` | `agent-team/owner-approval` |
| `state` | `success` (approved). `cos_approve_pr.py` never writes any other state. |
| `description` | `approve <N> by the user, <PREFIX>-<N>, item <message id>` (cut to GitHub's 140 characters) |
| `target_url` | none |
| creator | the Owner login (GitHub records it; `merge_pr.py` checks it) |

Why a status: GitHub ties it to one SHA, so a push leaves the new head with no record (a push voids it for free). The author can post it. Branch protection can require it by context. And it is not a review, so the rule "never submit a review" stays as it is.

### `scripts/cos_approve_pr.py`

- Add `author` to `PR_FIELDS`. The gates before the post don't change.
- When `author.login` equals the Owner login (case-insensitive), it is the **self-authored path**:
  - Already approved: the newest status in context `agent-team/owner-approval` on the head (`GET commits/<sha>/statuses`, newest first), created by the owner, is `success` → print `cos-approve: #N already approved by <owner> at <SHA>; nothing posted`, exit 0.
  - Otherwise `POST repos/{owner}/{repo}/statuses/<sha>` with the fields above. Last line: `cos-approve: approved #N at <SHA> (status; author is the owner)`. A failed POST is exit 2, `cos-approve: cannot post the status on #N: ...`.
- Any other author: today's review path, unchanged.
- The docstring and usage say which record each path writes.

### `scripts/merge_pr.py`

- Add `author` to `FIELDS`. For an open PR, also read `GET commits/<head>/statuses?per_page=100` into `f["statuses"]`.
- `read_protection` also returns whether `main` requires the status context `agent-team/owner-approval`. Classic: `required_status_checks.contexts` or `.checks[].context`. Ruleset: a `required_status_checks` rule whose `parameters.required_status_checks[].context` holds it. It returns `(count, requires_status, unread)`.
- New `self_approval(f)`, the twin of `owner_approval`. It returns `None` when all of these hold, else the reason:
  - The newest status in that context on `headRefOid` (by `created_at`; the API lists newest first) exists, was created by the Owner login, and is `success`. A newer `failure`, `error` or `pending` one, by anyone, voids it, and so does a status by any other login (the newest one wins and must be the owner's `success`).
  - No review on the PR in state `CHANGES_REQUESTED` was submitted after that status's `created_at`. That is any author's, since the owner can't review their own PR.
- In `gate()`, the protection and approval step becomes:
  - **Author is the owner:** stop unless `requires_status` is true (`main does not require the agent-team/owner-approval status; set it up per docs/agents/github-auth.md § Merge gate (owner-authored PRs)`). Stop if `count ≥ 1` (`main requires an approving review, which GitHub never lets the author give; ...`): GitHub would refuse that merge anyway, so the stop names the fix first. Then apply `self_approval(f)`.
  - **Any other author:** exactly today's checks (`count ≥ 1`, `owner_approval`).
  - The unread-protection message stays, and is also used when the source that would show the status requirement can't be read.
- Every other gate (approved head, green checks, both PASS reviews newer than the head or covered by a reviews-stand note, closeout docs, clean root `main`) runs as today on both paths.

### Branch protection (§ Merge gate in `github-auth.md`)

`main` has one protection, so the owner picks the setup that matches who opens PRs:

| Who opens PRs | What the owner sets on `main` |
|---|---|
| A builder account (Builder login set) | Today's setup, unchanged: CODEOWNERS `* @<owner>`, 1 required approval, Code Owners review, stale approvals dismissed, required checks, no bypass. |
| The owner (Builder login `none`) | Require a pull request, **0** required approvals, no Code Owners review. Required status checks: `agent-team/owner-approval` plus the repo's CI checks, "up to date" off. No bypass (enforce for admins, or an empty bypass list). |

With the second setup, GitHub itself refuses a merge whose head has no `agent-team/owner-approval` success, so a push after approval blocks the merge on the server as well as in the script.

The section also gets:
- The check commands for the status requirement (classic `--jq '.required_status_checks.contexts'`, ruleset `--jq '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context]'`).
- A plain note: a private repo on a free plan can't have either setup (403 "Upgrade to GitHub Pro"), and `merge_pr.py` then stops with `cannot read main's protection`.
- A replacement for the sentence "PRs must be opened by the builder user ... The gate cannot pass without that setup." It now says both paths are supported and points to the table.

### Docs and skills to update

Upstream in collective-wisdom (`agent-team/...`), installed here:

- `scripts/cos_approve_pr.py`, `scripts/merge_pr.py`, and their tests `scripts/test_cos_approve_pr.py` and `scripts/test_merge_pr.py`.
- `docs/agents/github-auth.md` § Merge gate (above).
- `.claude/skills/merge-pr/SKILL.md`: the Pre-merge checks list and Team mode say "the owner's approving review on the head, or, for a PR the owner wrote, the owner's `agent-team/owner-approval` status on the head". The `BLOCKED:` triggers add `no owner-approval status ...` and `main does not require the agent-team/owner-approval status ...`.
- `.claude/skills/ship-loop/SKILL.md` § Team mode (Relays) and `merge-pr` § Team mode: the "never submit a GitHub review" rule becomes "never submit a GitHub review, and never post a commit status in context `agent-team/owner-approval`, under any login"; the only exception is `cos_approve_pr.py` on a verified `approve N`.
- `.claude/skills/chief-of-staff/approvals.md` (merge block and reminder line): "this posts your approving review on GitHub" becomes "this posts your approval on GitHub (a review, or a status when you wrote the PR)". `chief-of-staff/SKILL.md` (§ Send or queue, the GitHub-is-read-only line) and `status.md` get the same wording, plus the new success line.
- `docs/agents/chief-of-staff.md` (what it writes on GitHub, the "Nothing was merged" line) and `docs/agents/org-chart.md` where it names the approving review.
- `agent-team/templates/project.md`: the Builder login note says that `none` means PRs are owner-authored and use the status path.

App-only, in this repo's own PR:

- `docs/agents/project.md`: the Builder login row note says that `none` means owner-authored PRs and the status path, with a pointer to `github-auth.md` § Merge gate. This is the app's filled copy, which the installer doesn't overwrite.
- This spec, its closeout (`**Shipped:**` line, as-built if needed) and the PR's `## Release note`.
- `docs/agents/installed-from.txt` and the installed files above, written by `scripts/agent-team-update.sh <new tag>`, with the command in the PR body.

### What the spec stage can and cannot deliver from this repo

- **Can:** this spec, committed and pushed on `feat/nh-29-owner-self-authored-approval`.
- **Cannot:** any change to the scripts, skills or shared docs above. By `ship-loop` § Team mode (Workflow files), they change only through a collective-wisdom PR for the same ticket, then an install PR here after a release tag. The build stage needs:
  1. A worktree of `~/collective-wisdom` (origin `collective-wisdom-org/collective-wisdom`, at `82211a2` today) on a branch `feat/nh-29-owner-self-authored-approval`, and a PR there. The Builder login is `none`, so the PR is opened as `noahstotland`, and that account needs push access to that repo.
  2. That PR merged and tagged (`tag-release.sh`) by whoever runs collective-wisdom. The Chief of Staff's merge relay covers only this repo's PR, so a NoHands child can't merge upstream.
  3. Then this repo's PR: `scripts/agent-team-update.sh <tag>` plus the app-only `project.md` note, through the usual code review, security review and `approve 29`.
  If step 2 doesn't happen in the same build run, the child stops with `BLOCKED: upstream PR <URL> needs merging and a tag` and resumes when it is relayed.
- **Cannot either:** the GitHub setting. No agent changes GitHub settings (`github-auth.md` § Merge gate). The owner sets protection by hand, after the § Blocker decision.

### Tests (upstream, in the existing table style)

`test_cos_approve_pr.py`, new `ROWS` (each changes one thing from a self-authored happy path, with `author` = `Owner`):

| Row | Exit | Posts | Line |
|---|---|---|---|
| self-authored, user's `approve 87` | 0 | 1 status (`context`, `state=success`, `sha=HEAD`) and no review | `approved #7 at <HEAD> (status` |
| self-authored, already a success status by the owner on head | 0 | 0 | `already approved` |
| self-authored, agent message only | 1 | 0 | `no verified` |
| self-authored, no message | 1 | 0 | `no verified` |
| self-authored, head moved | 1 | 0 | `not the approved head` |
| self-authored, status POST fails | 2 | 1 | `cannot post the status` |
| builder-authored happy path | 0 | 1 review, no status | unchanged |

`test_merge_pr.py`, new rows in `test_gate` (self-authored base facts: `author` = owner, protection `(0, True, [])`, a success status by the owner on head):

| Row | Cause |
|---|---|
| self-authored base | `None` (merges) |
| no status | `no owner-approval status` |
| status on an older head only (a push) | `no owner-approval status` |
| newest status is `failure` | `latest is failure` |
| newest status by another login (agent user or someone else) | `not by <owner>` |
| `CHANGES_REQUESTED` review after the status | `changes requested` |
| protection doesn't require the status | `does not require the agent-team/owner-approval status` |
| protection requires 1 approval | `requires an approving review` |
| builder-authored with only a status, no review | today's `no approving review by` (the status doesn't count for a builder PR) |

`test_read_protection` gets a row each for a classic `contexts`, a classic `checks` and a ruleset `required_status_checks` that hold the context, and one where they don't. All tests fake `gh`; none needs network or a T3 database other than the existing fixture.

## Security notes

- **Human gate kept.** The only writer of the record is `cos_approve_pr.py`, after `cos_user_check.latest` finds the user's own `approve N` (`createdBy: "user"`, after `lastSeenAt`, for that ticket's number) and the head equals `headSha`. Its gates are the ones that guard the review today.
- **Role accounts can't approve.** `merge_pr.py` accepts a status only when its creator is the Owner login, and only on an owner-authored PR. An agent user's status (when those logins exist) is not counted, and a newer one from them voids the owner's (fail closed).
- **The Chief of Staff can't approve for itself through a script.** `cos_approve_pr.py` refuses without the user's message. Skills forbid any other status write in that context.
- **The residual is the same as today's.** With every role `none`, every agent runs as the owner's gh account, so nothing in GitHub stops an agent from calling the statuses API by hand. The same is already true of the review API on a builder-authored PR when the Chief of Staff login is `none`. The guard is the skills' rule plus `merge_pr.py` running only on a relayed approval. Separate agent accounts are what close it, and this ticket leaves them out of scope. A status is not weaker than a review here: both are one API call from the owner's token.
- **Push voids it on both sides.** The status is per SHA, and `merge_pr.py` merges with `sha=<head>`. With the owner-authored protection, GitHub also requires the status on the head.
- Stale or replayed `approve N`: unchanged (`--after lastSeenAt`, word-boundary matching).

## Non-goals

- Letting the Chief of Staff approve without the user's message (NH-22).
- Creating the agent GitHub accounts.
- A script-only merge gate for repos without branch protection (see § Blocker; a separate call for the user).
- Changing the code review or security review rules.
- Merging the collective-wisdom PR or cutting its tag from a NoHands child.

## Calls I made

- ⚠ **Protection is still required, even though this repo can't have it on its plan.** Without Pro or a public repo, `approve N` still won't end in a merge here after this ships. I kept the gate rather than weaken it (§ Blocker, option 2 is yours to ask for).
- ⚠ **The record is a commit status (`agent-team/owner-approval`), not a comment.** A comment can be edited and isn't tied to a SHA. A status is tied to one head, can be required by branch protection, and needs no new kind of "review" exception.
- ⚠ **The owner-authored setup needs 0 required approvals and no Code Owners review on `main`.** A repo uses one setup or the other. A repo set up for builder PRs gets a clear stop on an owner-authored PR (and the reverse), not a fallback.
- The status path applies only when the PR author is the Owner login. A builder-authored PR with only a status doesn't merge (ticket: "exactly as before").
- The newest status in the context wins. Any non-success state, or one by another login, voids the approval. Any `CHANGES_REQUESTED` review after it voids it too, from any author.
- `cos_approve_pr.py` picks the path from the PR author itself; the Chief of Staff doesn't choose. There is no new flag.
- `merge_pr.py` doesn't re-read T3's message store. That would tie merges to T3 and change the solo flow; the user check stays in `cos_approve_pr.py`, as for reviews.
- The collective-wisdom branch uses this ticket's name, `feat/nh-29-owner-self-authored-approval`, so the "push only `feat/nh-29-*`" rule covers it.
- The status description holds the message id, not the user's words (140-character limit, and the words are already in the T3 thread).
