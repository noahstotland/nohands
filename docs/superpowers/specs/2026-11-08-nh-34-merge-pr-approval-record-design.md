# NH-34: Make merge_pr.py check the user's approval itself — Design

**Date:** 2026-11-08  **Ticket:** [NH-34](https://github.com/noahstotland/nohands/issues/34)
**Status:** Draft

## Intent

`scripts/merge_pr.py` only compares the PR head with the SHA its caller passes in. The check that the user really wrote `approve N` lives in `scripts/cos_approve_pr.py`, which the Chief of Staff runs before relaying. A role that skips the skills and calls `merge_pr.py` directly is stopped by nothing. This change makes `merge_pr.py` confirm the user's approval on its own, for the head it is about to merge.

## Where the change lives (needs your decision)

The ticket says this ships as a collective-wisdom PR plus an install PR here, and its acceptance list requires `docs/agents/installed-from.txt` to be updated. The ship loop's Workflow files rule and `AGENTS.md` say the same.

The Chief of Staff's relay asks for the change inside this app's `scripts/merge_pr.py` instead, "as the ticket says". The ticket does not say that. There is a real reason for the relay's direction, though:

- `scripts/agent-team-update.sh v0.2` refuses to install into an app (NH-67), so the install PR the ticket asks for can't be made from a current tag.
- NH-67 step 4 allows this order: "NH-34 lands before step 3, or moves upstream into collective-wisdom."

This spec follows the relay: an in-app change to `scripts/merge_pr.py` and its test file, with no collective-wisdom PR and no `installed-from.txt` bump. **Approving this spec means waiving that acceptance line and the Workflow files rule for this one ticket.** The approval needs to say so, because a relay alone can't change a rule that is on `main`.

The cost: NH-67 step 3 deletes this file, and v0.2's `merge_pr.py` has no `approve N` check (it checks a `user.md` login and, optionally, a teammate review). Unless the check also goes upstream, the protection ends when NH-67 lands. That follow-up is left out here and should be a ticket.

## Behaviour

After the existing "head equals approved SHA" gate, `merge_pr.py` looks for the user's approval and stops with `merge-pr: stop #N: <reason>` (exit 1) if any step fails. Nothing merges and nothing changes.

1. **Find the ticket.** In `.agent-team/state.json` on the root checkout, exactly one ticket has `pr` equal to this PR. None or several: stop.
2. **Stage.** That ticket is in stage `merge`. The Chief of Staff moves it there only after `cos_approve_pr.py` passes, and a withdrawn approval moves it back.
3. **Head.** The ticket's `headSha` equals the PR's current full head SHA, whatever SHA the caller passed.
4. **The user's message.** `cos_user_check.latest` on the thread in `chiefThreadId`, with the words `approve <ticket number>` and the cut-off below, must return a message with `createdBy: "user"` that isn't negated. An agent's copy of the words fails, as it does today.

**Cut-off.** The message must be newer than the latest of: the head commit's date, and the two latest PASS review comments. So a push after the approval voids it, and so does a new review.

An already merged PR returns before this check, so a repeat run for cleanup still works. The script writes nothing. A store or state read that fails exits 2 with `merge-pr: cannot read PR #N: ...`, like other read failures.

## How it's built

- `read_facts` gathers the approval result for open PRs into a new fact, using `cos_state.load` and `cos_user_check.latest` (imported the way `cos_approve_pr.py` loads them). `gate()` stays free of I/O and just reports it.
- No import cycle: neither module imports `merge_pr`.
- `cos_approve_pr.py` and the skills don't change.
- Tests in `scripts/test_merge_pr.py`, one table, using a temporary SQLite store like `scripts/test_cos_approve_pr.py`. Passes with a valid approval, including an owner-authored PR. Refuses with: no ticket for the PR, wrong stage, `headSha` for another head, no message, a message older than the head commit or a review, `createdBy: "agent"`, a negated message, and a caller passing the current head with no approval.

## Calls I made

- **In-app change, against the ticket's written acceptance.** See above. Your approval has to cover it.
- **Solo merges are refused.** A `merge it` in a session with no Chief of Staff has no state entry and no `approve N`, so `merge_pr.py` stops. The ticket's acceptance asks for this ("whatever SHA the caller passes"), and any bypass flag would be open to the same roles this closes off. Solo merges would go through the team's `approve N`, or GitHub by hand.
- **The record is checked at the source, not written to a new file.** The ticket lets this PR pick the mechanism. A record file or PR comment could be written by any role on this machine, or by anyone using this `gh` login. T3 stamps `createdBy` on the user's messages, so reading the message store needs no new secret and works when the PR author and the owner are the same account.
- **`lastSeenAt` is not the cut-off.** `cos_approve_pr.py` uses it, but the Chief of Staff's sweep rewrites it on every read of a ticket in `merge`, so it would refuse good approvals. The cut-off above uses the commit date and GitHub's own review comment times.
- **Stage `merge` only, not `awaiting-merge` or `merge-queued`.** The Chief of Staff sends the relay just before writing that stage, so a very fast child could be refused. It would stop with `BLOCKED:` and a resume clears it. I took that over accepting a stage where the approval may have been withdrawn.
- **A Chief of Staff rotation needs a new `approve N`** if it lands between the approval and the merge, because the check reads only the current `chiefThreadId`. `cos_approve_pr.py` already behaves this way before the relay.
- **Skill and doc wording stays as it is.** The `merge-pr` check list and `github-auth.md` § Merge gate won't name the new check. Changing them is more of the same exception, and NH-67 removes those copies.

## Limits

- This stops a role that ignores the skills. It doesn't stop one that deliberately edits `state.json`, backdates a commit and has a matching real `approve N`, or that writes to T3's database. Those run as your user on your machine.
- This PR merges under the old gate on root `main`, so the new check first runs on the next merge. No live merge is run as part of this ticket.

## Out of scope

- A collective-wisdom PR or moving this check upstream (see above).
- Negated approvals beyond what `cos_user_check` already rejects.
- Letting the Chief of Staff approve without the user's message (NH-22).
- Any change to the app's Swift code.
