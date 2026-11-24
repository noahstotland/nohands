# NH-29: Let the owner approve and merge PRs they authored themselves — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-29](https://github.com/noahstotland/nohands/issues/29)
**Shipped:** in PR #30, as specified

## Goal

Make `approve N` end in a merge for a PR the owner wrote, in this repo, without weakening the rule that only the user's own verified `approve N` in the Chief of Staff thread starts a merge. Scope: **one install PR in this repo** plus a `project.md` cleanup. No upstream PR, no new approval mechanism.

## Why the scope shrank

Earlier revisions added a commit-status approval record and a `script-only` merge-gate setting. Upstream (`d3df944`, 41 commits past the installed `82211a2`) already removed both problems in CW-110:

- `cos_approve_pr.py` posts nothing. It verifies the user's `approve N`, the Owner login, and the PR open, not a draft, on `main` at the recorded head. No review, no 422.
- `merge_pr.py` has no branch-protection check. It merges only if the head equals the relayed one, with CI, both PASS reviews and closeout green.
- The per-agent logins (`AGENT_GH_ROLE`, `git.sh`, `personas.md`, four `project.md` login rows) are gone.

The proof is still the user's own message, checked in T3's message store. A push after approval changes the head and needs a new `approve N`. The installed scripts post a review (422 on owner-authored PRs) and need branch protection (403 here), so both fail.

## The install

No upstream tag exists, so the build runs `bash install.sh --update --to <sha> <this worktree>` from a fresh clone (allowed by `ship-loop` § Team mode) and pins that exact commit, not a floating `origin/main`. If a `v0.N` tag at or after `d3df944` exists by build time, use `agent-team-update.sh v0.N` with `COLLECTIVE_WISDOM_REPO` set to the `collective-wisdom-org` URL.

## Design

Build in this repo's own PR:

1. Dry-run the installer and list the file changes in the PR body.
2. Install. Don't hand-edit installed files.
3. Reconcile `docs/agents/project.md`: remove the four login rows, add missing template rows, keep the `Approver` row and all NoHands text.
4. Check nothing app-side uses the removed scripts.
5. Verify: `python3 -I -m pytest -q scripts`, `swift build`, `swift test`.
6. Closeout with a `## Release note`.

No new tests: installed files are tested upstream.

## Risks

- **41 upstream commits nobody here has read.** Code and security review get an explicit instruction to read the approval path (`cos_approve_pr.py`, `merge_pr.py`, `cos_user_check.py`).
- **It replaces the running Chief of Staff skill.** Running threads keep the old rules; rotate the thread after the merge.
- **NH-29's own PR goes through the old scripts,** so `approve 29` can't pass. The user merges this one PR by hand on GitHub.
- **GitHub enforces nothing on `main`.** The guards are the skills' rules (only `merge_pr.py` merges; never push to `main`) and the relayed approval. This is upstream's design, accepted here.

## Leaves out

A new approval record or `script-only` setting; any upstream PR or tag; GitHub settings changes.

## Calls I made

- Pin a fixed commit, so the PR is reviewed against a fixed target; later upstream commits come in a later update.
- **The pin moved to `c8bf556`** (1 commit after `d3df944`). The first security review found a merge child could pass a head pushed after approval; upstream fixed it in `9cbc1ee` (a moved head ends in `BLOCKED: head moved after approval`, and `merge_pr.py` checks the owner login).
- `project.md` loses the four login rows; everything NoHands-specific stays.
- The commit-status approval and `script-only` row are dropped, since upstream no longer has the checks they worked around. The user said "1" to this scope.
