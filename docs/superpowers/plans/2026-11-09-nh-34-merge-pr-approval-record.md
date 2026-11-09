# NH-34 plan: merge_pr.py checks the user's approval itself

Spec: `docs/superpowers/specs/2026-11-08-nh-34-merge-pr-approval-record-design.md` (approved). All code is in collective-wisdom, built in a separate clone on branch `feat/nh-34-merge-pr-approval-record`, under `agent-team/`. `~/.collective-wisdom` is the live install and is never edited.

Test command (from the clone root): `uvx pytest -q agent-team/scripts` (or `python3 -I -m pytest -q agent-team/scripts`).

## Task 1: share the auto rule

Move `auto_gate` from `cos_approve_pr.py` to `approval_policy.py` unchanged, and make `cos_approve_pr.py` call it. `merge_pr.py` can't import `cos_approve_pr` (that module imports `merge_pr`). Check that `test_approval_policy.py`'s rule about local imports of listed gate scripts still passes. Acceptance: the existing `test_cos_approve_pr.py` and `test_approval_policy.py` pass untouched.

## Task 2: the check in merge_pr.py

In `read_facts` (open PRs only) gather an `approval` fact; in `gate()` report it right after the head check. Steps and messages are spec § Behaviour: no `.agent-team/state.json` is a `merge-pr: warn` and the old gates; otherwise exactly one ticket with this `pr`, stage `merge`, `headSha` equal to the record head (the PR head, or the reviewed first parent when `resolved_head` accepts), then the user's `approve <N>` via `cos_user_check.latest` or the auto rule. Cut-off: the latest of the record head's commit date and the code and security review comments (outside `ci` review mode). A state or store that exists but can't be read exits 2.

## Task 3: tests

One table-driven test in `test_merge_pr.py` using a temporary state file and SQLite store (style of `test_cos_approve_pr.py`). Rows are listed in the spec § How it's built. Each refusing row must fail against the unchanged script.

## Task 4: docs

Update the `merge_pr.py` docstring check list, `merge-pr` § Gate, the hand-run lines in `ship-loop` § Approvals, and `github-auth.md` § Merge gate so they match the new behaviour. Wording only; no rule beyond the spec.

## Task 5: collective-wisdom PR

Include a copy of the spec at the path collective-wisdom's closeout check expects (as PR #123 did). Open via `open-pr` rules in that repo.
