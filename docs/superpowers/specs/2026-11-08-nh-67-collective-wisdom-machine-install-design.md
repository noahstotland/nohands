# NH-67: Move this app to the collective-wisdom machine install (v0.2) — Design

**Date:** 2026-11-08
**Status:** Draft
**Ticket:** [NH-67](https://github.com/noahstotland/nohands/issues/67)

## Goal

Run the agent team on collective-wisdom v0.2. v0.2 installs once per machine, so this app stops carrying its own copy. A solo owner's `approve N` must still end in a merge.

## Today

Checked 2026-11-08 on this repo's `main` (`29b0f38`) and upstream tag `v0.2` (`cbc35dc`, also upstream `main`).

- This app runs a copy of collective-wisdom `f49afcc`. `scripts/agent-team-update.sh v0.2` exits 2, because `install.sh` refuses `--update` from v0.1 on.
- `remove_app_copies.py` at v0.2, dry-run in this worktree: 103 files plus the `.agents/skills` link, about 14,000 lines, no hand-edited copies. Of the agent-team copies, only `docs/agents/project.md` and `.claude/settings.json` stay. The app's own `scripts/bundle.sh`, `scripts/setup-local-model.sh` and two `scripts/intent-eval*.json` fixtures also stay.
- Outside the removal list, only `AGENTS.md` and `docs/agents/project.md` point at removed files. `README.md` only names the app's own scripts.
- `.claude/settings.json` holds one thing: a Stop hook that calls `scripts/cos_rotation_check.py`, which the removal deletes.
- This Mac has no `~/.collective-wisdom`, no `~/.config/collective-wisdom/` and no `~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md`. None of the v0.2 skill or agent names collide with an existing entry under `~/.claude`, `~/.agents` or `~/.cursor`.
- `~/collective-wisdom` already exists: a real clone on local `main` at the old `82211a2` (ahead 48, behind 77, from the org history rewrite), with a linked worktree from NH-29.
- `~/.t3/projects/frenly` also runs the team, from its own copy pinned at `d3df944`. `disc-chirper` and `nohands-voice-control` have no `project.md`, so the team stays off there.

### What v0.2 does to the merge gate

From reading the v0.2 code. No live merge was run.

- `merge_pr.py` and `cos_approve_pr.py` need `gh` signed in as the login that `~/.config/collective-wisdom/user.md` maps to this repo. With no row, every merge stops. That row is the one new requirement.
- `cos_approve_pr.py` without `--auto` still needs the user's own `approve N`, through `cos_user_check.py`.
- `Require teammate approval` is off when its row is missing. `reviewDecision` only stops a merge when GitHub requires reviews, and this repo has no branch protection. So no new reviewer or branch rule is needed.
- A missing `Approval risk tolerance` row reads as `strict`, and the No Hands setting is on only if its row says `on`. This repo has neither row and this ticket adds neither, so nothing here turns on auto-approval (NH-22).
- `setup_repo.py status` at v0.2 reads this repo's `project.md` as `set`.
- Upstream's `test_merge_pr.py`, `test_cos_approve_pr.py`, `test_user_config.py` and `test_remove_app_copies.py` pass at v0.2 (223 passed, run in a scratch clone).

## Ordered steps

| # | Step | Who |
|---|---|---|
| 1 | Machine install | **Needs the user's explicit go-ahead** |
| 2 | `user.md` row | **Needs the user's explicit go-ahead** |
| 3 | Check 1 and 2 worked | Build child, read-only |
| 4 | Dry-run the removal | Build child |
| 5 | Remove the copies | Build child, in this worktree |
| 6 | Remove the old Stop hook | Build child |
| 7 | Fix references | Build child |
| 8 | Verify | Build child |
| 9 | PR, reviews, closeout | Build child |
| 10 | Merge with the machine copy | Build child, after the user's `approve N` |
| 11 | Rotate the Chief of Staff | Chief of Staff |

Approving this spec does not grant steps 1 and 2. The user either runs them, or says in the Chief of Staff thread that an agent may run them, naming them. A relay has to quote that. Without it, the build stops at step 3 with `BLOCKED:` and these commands.

**Step 1. Machine install.** Writes under `$HOME` only, and applies to every repo on this Mac.

```sh
git clone https://github.com/collective-wisdom-org/collective-wisdom.git ~/collective-wisdom-release
cd ~/collective-wisdom-release && git checkout --detach v0.2
./install.sh --dry-run
./install.sh
```

It creates the `~/.collective-wisdom` link and one link per skill and agent, adds a Stop hook to `~/.claude/settings.json`, and creates `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` with the team's instruction block. The clone needs full history, because the removal reads `f49afcc` from it, so no `--depth`. Its `TODO:` list ends with text to paste into Cursor's user rules, which is only needed if Cursor is in use.

**Step 2. `user.md` row.** No tokens go in this file.

```sh
python3 -I ~/.collective-wisdom/scripts/setup_repo.py user --login noahstotland --repo-key github.com/noahstotland/nohands
```

**Step 3. Check.** All read-only, from this worktree. Any failure is `BLOCKED:` with the output.

- `readlink ~/.collective-wisdom` ends in `agent-team`, and that clone's `git describe --tags --exact-match` prints `v0.2`.
- `python3 -I ~/.collective-wisdom/scripts/user_config.py account` prints `github.com noahstotland`.
- `~/.collective-wisdom/scripts/gh.sh api user -q .login` prints `noahstotland`.

**Step 4. Dry-run.** `python3 -I ~/.collective-wisdom/scripts/remove_app_copies.py --dry-run`, file list into the PR body. A `changed <path>` line stops the build with `BLOCKED:`. `--force` is never used here.

**Step 5. Remove.** The same command without `--dry-run`, then an `infra:` commit. From here on the build calls `~/.collective-wisdom/scripts/gh.sh`, `wait-for-ci.sh` and `pr_diff_delta.py`, since this worktree's copies are gone.

**Step 6. Stop hook.** Remove the hook, leaving `.claude/settings.json` as `{}`.

**Step 7. References.** Only references to removed files change. Every app-specific value stays.

- `AGENTS.md` § Required reading and § GitHub: `~/.collective-wisdom/docs/agents/org-chart.md`, `README.md`, `security-review.md`, `github-auth.md`, and `~/.collective-wisdom/scripts/gh.sh`.
- `AGENTS.md` § Agent config: skills and subagents come from the machine install. To update, check out a newer tag in the clone and rerun `./install.sh`. Drop the `.claude/skills/`, `.agents/skills`, `.claude/agents/` and `agent-team-update.sh` lines.
- `docs/agents/project.md`: machine paths in the `GitHub CLI`, `Docs index listing` and `Release notes listing` rows, the `release-notes` exception in § Repo invariants, and the `trackers/`, `github-auth.md` and `documenter.md` links, in the form v0.2's template uses. Delete the `Agent-team script tests` row. § Docs check lists `docs/agents/project.md` in place of `docs/agents/` and drops `.claude/skills/`.

**Step 8. Verify.**

- `swift build` and `swift test` pass. No Swift file changes.
- `git ls-files scripts docs/agents .claude .agents` lists only the six files that stay.
- A grep of `AGENTS.md` and `project.md` for `./scripts/gh.sh`, `installed-from`, `agent-team-update` and the removed doc paths finds nothing.
- `setup_repo.py status` prints `set`, with `mapped_login` `noahstotland`.
- Upstream's four merge-gate test files pass from the machine clone, with `PYTHONDONTWRITEBYTECODE=1` and `-p no:cacheprovider` so the clone stays clean.

**Step 9. PR.** Normal phases 3 and 4, with reviewers using `git diff origin/main...HEAD`. The body names every `scripts/test_*.py` removed, what changes for this team (below), and `## Proof` with `Not proven`.

**Step 10. Merge.** After the user's `approve N`, run `python3 ~/.collective-wisdom/scripts/cos_approve_pr.py NH-67` and `python3 ~/.collective-wisdom/scripts/merge_pr.py <PR> <head>` from the root checkout, not the copies in the root's `scripts/`. The old `merge_pr.py` fast-forwards root, which deletes its own `gh.sh`, and then calls that `gh.sh` to publish release notes. The merge would land and the publish would fail.

**Step 11. Rotate.** A running Chief of Staff still has `./scripts/...` in its context, and those calls fail after the merge. It rotates right after the merge, and children started before it finish against their own worktree's copies.

## What changes for this team

- Stage `awaiting-spec` becomes `awaiting-build` and the marker `SPEC READY` becomes `BUILD READY`. v0.2 converts old state on load and still accepts the old marker.
- New `project.md` settings, all default-off or default-same when the row is missing: `Approval risk tolerance`, `No Hands`, `Require teammate approval`, `Review mode`, `Merge target branch`, `Review after conflict resolution`, `Publish release notes`. This ticket adds none.
- New `awaiting-review` stage (only with required reviews or teammate approval), a local dashboard started by `start the team`, and a docs check that runs once after both reviews pass.
- There is no pin per app any more. Updating is `git checkout v0.N && ./install.sh` in the clone, for every repo at once.

## NH-34

NH-34 moves upstream entirely and changes nothing in this app.

- NH-34's goal still stands: `merge_pr.py` at v0.2 has no approval record. Its ticket already says the fix belongs upstream.
- After this ticket there is no app copy to change. The fix ships as a collective-wisdom PR and a new tag, and this Mac takes it with step 1's update command. NH-34's "install PR here" and its `installed-from.txt` acceptance line no longer apply. The Chief of Staff updates that ticket, since a child changes only its own.
- NH-67 does not wait for NH-34. If an NH-34 change to `scripts/merge_pr.py` reaches this app's `main` first anyway, step 4 reports `changed scripts/merge_pr.py` and the build stops.

## Tests

No new tests. This PR deletes copied files and edits prose. `swift test` covers the app, and upstream's tests cover the scripts where they now live.

## Risks

- **Step 1 reaches every repo on this Mac.** Skills at user level may take precedence over a repo's own copies, so `frenly` may start using v0.2 skills while still holding its `d3df944` copy. Its merges would need their own `user.md` row. Moving `frenly` is not part of this ticket.
- **Between step 1 and the merge, two copies exist.** New threads may read the v0.2 skills while `scripts/` still exists. Both gates pass once step 2 is done, so the order is safe either way.
- **Open branches lose their `scripts/` copies when they merge `main`.** PRs #19 and #20 touch none of the removed paths.
- **Undo.** Reverting the PR restores the copies. The machine install stays and can be undone separately by removing its links.

## Not proven

- No live merge run. The `approve N` claim comes from reading v0.2's code and upstream's tests.
- Whether a user-level skill or a repo-level skill wins in T3 Code during the overlap has not been tested. The design holds either way.

## Non-goals

- `Approval risk tolerance`, No Hands, auto-merge or any auto-approval (NH-22).
- Changing shared skills or scripts here. Those change in collective-wisdom.
- Moving `frenly`, or touching `~/collective-wisdom`.
- Running `./install.sh` or writing `user.md` without the user's go-ahead.

## Calls I made

- ⚠ **A new clone at `~/collective-wisdom-release`, not the existing `~/collective-wisdom`.** The whole team runs from whatever the machine clone has checked out, so a branch switch for upstream work (NH-34) would change every repo's team mid-run.
- ⚠ **This PR merges through the machine copy of `merge_pr.py`,** because the old copy deletes its own `gh.sh` partway through.
- ⚠ **`frenly` is left as is,** with the risk above. It may need its own `user.md` row if the team runs there.
- ⚠ **Approving this spec is also the go-ahead to replace the Workflow files rule in `ship-loop`** (install PR that bumps `installed-from.txt`), which v0.2 no longer has a way to follow. It does not grant steps 1 and 2.
- NH-34 moves upstream, not ahead of this ticket in the app.
- `.claude/settings.json` stays as `{}` instead of being deleted, because the ticket lists it as staying.
- The `Owner login` row in `project.md` stays. v0.2 no longer reads it, but removing it isn't a reference fix.
- Pinned to `v0.2` by a detached checkout rather than following upstream `main`, as the user asked for the pinned release.
