# NH-29: Let the owner approve and merge PRs they authored themselves — Design

**Date:** 2026-11-05  **Status:** Draft  **Ticket:** [NH-29](https://github.com/noahstotland/nohands/issues/29)

## Goal

Make `approve N` end in a merge for a PR the owner wrote, in this repo, without weakening the rule that only the user's own verified `approve N` in the Chief of Staff thread starts a merge. This revision shrinks the ticket to **one install PR in this repo** plus a `project.md` cleanup. No upstream PR and no new approval mechanism.

## Why the scope shrank

- Revisions 1 and 2 of this spec (commits `df32d03`, `ff099fd`) were written against collective-wisdom `82211a2`, the version in `docs/agents/installed-from.txt`. They added a commit-status approval record and a `script-only` merge-gate setting.
- Upstream `origin/main` (`d3df944`) is 55 commits ahead. Commit `2e870c2` (CW-110, #111, "remove the per-agent GitHub users, thread approval is the merge proof") already removed both problems. Checked 2026-11-05 in the upstream tree:
  - `scripts/cos_approve_pr.py` posts nothing. It verifies the user's `approve N` (`cos_user_check.py latest`), gh signed in as the Owner login, and that the PR is open, not a draft, based on `main` and still at the head in the state file, then exits 0. There is no review to refuse, so no 422.
  - `scripts/merge_pr.py` has no `read_protection` or `owner_approval`. It merges only if the head equals the relayed one, and checks mergeable state, CI, both PASS reviews, closeout and root-checkout state. So the "cannot read main's protection" stop is gone too.
  - `docs/agents/github-auth.md` § Merge gate says nothing in the team submits a GitHub review and the gate needs no branch protection, ruleset or CODEOWNERS file.
  - `AGENT_GH_ROLE`, `git.sh`, `personas.md`, `project_config.role_login` and the four login rows in the `project.md` template are gone.
- The human gate is unchanged in kind: the proof is the user's own message, checked by `cos_approve_pr.py` in T3's message store. A push after approval changes the head, so it needs a new `approve N`.

## Today

Facts from this repo's `main` (`ff9e08b`), checked 2026-11-05.

- Installed from collective-wisdom `82211a2`, pinned as a SHA with no tag (`docs/agents/installed-from.txt`).
- `docs/agents/project.md` § Git and GitHub has the four rows `Chief of Staff login`, `Builder login`, `Code reviewer login` and `Security reviewer login`, all `none`, with notes that link to `github-auth.md` § Agent users. That section no longer exists upstream.
- The installed scripts post a review (`cos_approve_pr.py`) and require branch protection (`merge_pr.py`). Both fail here: the review gets a 422 on owner-authored PRs, and `GET .../branches/main/protection` and `.../rules/branches/main` return 403 "Upgrade to GitHub Pro" on this private repo.
- Files that mention the removed machinery, from a grep for `AGENT_GH_ROLE`, `Agent users`, `personas.md` and `git.sh`: skills (`write-ticket`, `project-manager`, `open-pr`, `merge-pr`, `chief-of-staff`, `ship-loop`, `security-review`), `docs/agents/` (`README.md`, `org-chart.md`, `github-auth.md`, `personas.md`, `project.md`, `trackers/github.md`), and scripts and tests (`gh.sh`, `git.sh`, `cos_brief.py`, `cos_approve_pr.py`, `merge_pr.py` and their tests). All of them except `project.md` are shipped files the installer replaces.

## The latest tag

Checked 2026-11-05 with `git ls-remote --tags origin` on `collective-wisdom-org/collective-wisdom`: **no tags exist**, so no `v0.N` tag is at or after `d3df944`. `scripts/agent-team-update.sh` with no tag stops (`no v0.N tag on origin/main`), and `<tag>` needs a tag that exists. Also, the installed copy of `agent-team-update.sh` clones `https://github.com/dbeallor/collective-wisdom.git`, the old location (upstream repointed to `collective-wisdom-org` in #118). The new copy fixes that, but the old one runs first.

So the install runs one of two ways. The build tries them in this order:

1. **A tag exists by build time** (the maintainer ran `tag-release.sh` after `d3df944`): `scripts/agent-team-update.sh v0.N`, with `COLLECTIVE_WISDOM_REPO=https://github.com/collective-wisdom-org/collective-wisdom.git` set for the first run, since the installed script's default URL is the old one.
2. **No tag** (today): from a fresh clone of upstream at the pinned commit, `bash install.sh --update --to d3df944 <this worktree>`. `ship-loop` § Team mode (Workflow files) allows "install.sh --update from a clone". The pin records the SHA with no tag. The ticket doesn't wait for a tag, and pins an exact commit, not a floating `origin/main`.

Either way the PR body lists the exact command it ran, and the pin line in `installed-from.txt` changes.

## Design

The build, in this repo's own PR (`feat/nh-29-owner-self-authored-approval`):

1. **Preview.** Run the installer with `--dry-run` first. Put the list of changed, added and removed files in the PR body.
2. **Install** with the command above. Don't hand-edit installed files. If `install.sh` reports drift (local edits to shipped files), stop and read it; use `--force` only for files whose local edits the spec lists as safe to drop, and none are expected.
3. **Reconcile `docs/agents/project.md`** (app-only, the installer never overwrites it):
   - Remove the four login rows (`Chief of Staff login`, `Builder login`, `Code reviewer login`, `Security reviewer login`).
   - Add any row the new template requires that this file lacks (the build diffs the new `agent-team/templates/project.md` against this file and lists each difference in the PR).
   - Keep the `Approver` row, the repo invariants, product rules, security overlays and all NoHands-specific text.
4. **Check nothing app-side still needs the removed scripts.** `grep` for `git.sh`, `gh.sh`, `AGENT_GH_ROLE`, `personas.md` and `Agent users` outside installed files. The root `AGENTS.md` instructions say to use `./scripts/gh.sh` and `docs/agents/github-auth.md`; confirm both still exist after the update, and fix `AGENTS.md` only if they don't.
5. **Verify.** `python3 -I -m pytest -q scripts` (the agent-team script tests), `swift build` and `swift test` stay green. No Swift file changes in this PR. A dry read of the new merge path: `python3 scripts/cos_approve_pr.py --help` and `python3 scripts/merge_pr.py` with no arguments both print usage.
6. **Closeout.** This spec gets `**Status:** Shipped` and `**Shipped:** in PR #N, as specified` (or an as-built if the install differs), and the PR body gets a `## Release note` and whatever sections the new `open-pr` requires (CW-107 added a `Proof` section).

### Tests

No new tests. The change is installed shipped files, whose upstream tests come with them and run in step 5, and one config file with no parser logic of its own beyond `project_config.py`, which the installed tests cover.

### What the spec stage can and cannot deliver

- **Can:** this spec, committed and pushed.
- **Cannot:** the install itself. It happens in the build stage after a relayed spec approval.

## Risks and what changes after this ships

- **Unreviewed upstream code.** The update pulls in about 55 upstream commits (`82211a2..d3df944`) that nobody here has read. The code and security review of the PR cover the diff, which is large (most shipped scripts, skills and docs). The reviewers read the changes to `cos_approve_pr.py`, `merge_pr.py`, `cos_user_check.py` and the approval wording on purpose.
- **It changes the Chief of Staff skill itself.** `.claude/skills/chief-of-staff/` and its scripts (`cos_*.py`) are replaced while a Chief of Staff thread is running on the old copy. Running threads read their skills when they load them. After the merge, the Chief of Staff and children started later run the new rules; running ones keep the old rules in context. The Chief of Staff should rotate its thread after the merge, so it reads the new skill.
- **NH-29's own PR still goes through the old scripts.** Until it merges, root `main` has the old `cos_approve_pr.py` (posts a review, 422 on an owner-authored PR) and `merge_pr.py` (needs protection). So `approve 29` on this PR can't pass the old gate. The user merges this one PR by hand on GitHub, after reviewing it. From the next ticket on, `approve N` uses the new scripts. The Chief of Staff's merge block for NH-29 must say so.
- **In-flight tickets.** Any open PR written against the old closeout or review rules (for example, the new `Proof` section) may need a small PR-body fix after this merges. The build lists open PRs at that time.
- **The gate is the user's message, nothing else.** With no protection and no review, GitHub enforces nothing on `main`. Anyone with write access can merge from the web or push to `main`. The guards are the skills' rules (only `merge_pr.py` merges; never push to `main`) and the relayed approval. This is upstream's design after CW-110, accepted here.

## Non-goals

- A new approval record, a commit status, or a `script-only` setting (dropped; see § Why the scope shrank).
- Any upstream collective-wisdom PR, or tagging a release from here.
- Creating GitHub accounts, upgrading the plan, or changing GitHub settings.
- Changing the code review or security review rules beyond what the update brings.
- Review of the 55 upstream commits one by one, outside the PR's own reviews.

## Calls I made

- ⚠ **The update replaces the Chief of Staff skill and scripts that are running now.** The new copy takes effect for new threads. Rotate the Chief of Staff thread after the merge.
- ⚠ **NH-29's own PR merges by hand.** The old gate on root `main` can't pass it (422, and no branch protection). You review it and merge it on GitHub once.
- ⚠ **About 55 upstream commits arrive unreviewed except by this PR's own code and security review.** The reviewers get an explicit instruction to read the approval path (`cos_approve_pr.py`, `merge_pr.py`, `cos_user_check.py`).
- **No tag exists upstream today.** The build installs with `install.sh --update --to d3df944` from a clone and pins that commit. If a `v0.N` tag at or after `d3df944` exists by build time, it uses `agent-team-update.sh v0.N` instead, with the new repo URL for the first run.
- I pin `d3df944`, not the newest `origin/main`, so the PR can be reviewed against a fixed target. Later upstream commits come in a later update.
- `project.md` loses the four login rows; everything NoHands-specific stays. The build copies new template rows only where they are missing.
- No Swift, no tests, no `README.md` change: the PR touches only shipped agent-team files and `docs/agents/project.md`.
- I dropped the commit-status approval and the `script-only` row from the earlier revisions, because upstream no longer has the review or protection check they worked around. You said "1" to this scope in the thread.
