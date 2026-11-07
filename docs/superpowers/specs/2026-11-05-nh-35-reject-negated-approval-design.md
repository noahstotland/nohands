# NH-35: Make cos_user_check.py reject a negated approval — Design

**Date:** 2026-11-05
**Status:** Shipped
**Ticket:** [NH-35](https://github.com/noahstotland/nohands/issues/35)
**Shipped:** in PR #64, with differences: [as-built](../as-built/2026-11-05-nh-35-reject-negated-approval.md)

## Goal

"do not approve 30 yet" must not count as the user's `approve 30`. `scripts/cos_user_check.py` (`latest` and `item`) should fail closed when the command's words are negated in the user's message, and still pass a plain `approve N`.

## Today

Checked 2026-11-05 on this repo's `main` (`d6eec6f`, installed from collective-wisdom `c8bf556`) and on collective-wisdom `origin/main` (also `c8bf556`; upstream has no newer commits and no tags).

- `latest` takes the newest user-role message in the thread whose text contains the words (`has_words`: NFKC, zero-width removal, whitespace collapse, case fold, token boundaries). It never looks at the words around the match. `item` uses the same `has_words`.
- So "don't approve 30" and "never approve 30" pass as `approve 30`. `scripts/cos_approve_pr.py` calls `latest(..., "approve N", lastSeenAt)` and `merge_pr.py` keeps no approval record of its own, so such a message could start a merge.
- `latest` serves every Chief of Staff command (`approve N`, `changes N`, `cancel N`, `status`, `stop everything`, `resume`) and, in `cross-repo.md`, the user's whole message as the words.
- `scripts/cos_peer.py` imports `has_words` to match repo names and stored request words. It must not change.

## Design

All code changes are upstream, in `agent-team/scripts/cos_user_check.py` and its test in collective-wisdom. This repo gets them through an install PR.

### The rule

A match is **negated** when the same sentence holds a negation word outside the matched words, before or after them.

- **Sentence:** the normalized text (the existing `norm`) is cut at `.`, `!`, `?` or `;` followed by whitespace or the end of the text. A period inside a token (`v0.3`, `ABC-5.1`) does not cut. Line breaks do not cut either, because `norm` already folds them into spaces.
- **Negation word:** a token (`[\w']+`, after mapping `’`, `‘` and `ʼ` to `'`) that is `no`, `not`, `never`, `nor`, `cannot`, `dont`, `cant` or `wont`, or that ends in `n't` (`don't`, `won't`, `shouldn't`, `isn't` and so on). "do not" is caught by `not`.
- Words inside the match itself are ignored. That keeps the whole-message check in `cross-repo.md` working, where the words are the entire message and nothing lies outside them.
- If any occurrence of the words in the message is negated, the message is negated.

A new helper `command_in(words, text)` returns `None` (no match), `"negated"` or `"ok"`. `has_words` stays as it is for `cos_peer.py`.

### Output

- `latest` still picks the newest user-role message containing the words, negated or not. It does not fall back to an older message: the newest one is what the user last said. When that message is from the user but negated, it prints `not-user negated <itemId> <first 80 characters>` and exits 1. Agent and missing authors print as today. Callers already treat any `not-user` line and exit 1 as "not the user's command" (`cos_approve_pr.py` stops with the line in its reason).
- `item` prints `reject: words negated` and exits 1.
- The module docstring describes the rule. `chief-of-staff/SKILL.md` § "A command or answer counts as the user's only if" gets one sentence: a `not-user negated` line means the user's message says not to, so nothing runs and nothing is reported as approved.

### Tests

One new table in `agent-team/scripts/test_cos.py`, next to `test_user_check`, run through both `latest` and `item` against the same rows (words `approve 30`):

| Message | Result |
|---|---|
| `approve 30` | pass |
| `approve 30 please` | pass |
| `ok, approve 30` | pass |
| `no. approve 30` | pass (the "no" is its own sentence) |
| `approve 30 and leave 31 alone` | pass |
| `do not approve 30 yet` | negated |
| `don't approve 30` | negated |
| `Don’t approve 30` (curly apostrophe) | negated |
| `dont approve 30` | negated |
| `never approve 30` | negated |
| `not yet, approve 30 later` | negated |
| `approve 30, no rush` | negated |
| `approve 30 not yet` | negated |

Plus one `latest` row where a negated message is newer than a plain `approve 30`: it fails (`not-user negated`), it does not fall back. The existing `test_user_check` rows, including `ok, approve ABC-5 now`, keep passing.

### Delivery

1. **Upstream PR** in `collective-wisdom-org/collective-wisdom`, branch `feat/nh-35-reject-negated-approval` from `origin/main`, the same way NH-29 went (upstream #123): code, test, docstring, the SKILL.md sentence and a short upstream spec. `uvx pytest -q agent-team/scripts` and `shellcheck` per its `CONTRIBUTING.md`. Code review and security review comments on that PR, to PASS.
2. **Upstream merge.** `install.sh --update --to` only takes a commit on upstream `origin/main`, so the upstream PR has to merge first. Nothing in this team merges outside `merge_pr.py`, so the build stops there with `BLOCKED: collective-wisdom PR #N is review-PASS and needs your merge` and waits for a relay.
3. **Install PR** here on this branch: `bash install.sh --update --to <merged upstream SHA> <this worktree>` from a fresh clone (no tags exist upstream; if a `v0.N` tag at or after that SHA exists by then, `scripts/agent-team-update.sh v0.N` instead). `--dry-run` first, file list in the PR body. `docs/agents/installed-from.txt` changes with it. Then `python3 -I -m pytest -q scripts`, `swift build`, `swift test`, and the usual phases 3 and 4 to `MERGE READY`.

No Swift files change.

## Non-goals

- An approval record in `merge_pr.py` (separate ticket).
- Reading intent beyond negation: "wait", "hold off", "later", sarcasm, questions ("approve 30?") and conditionals ("approve 30 if CI passes") still pass. The Chief of Staff's own read of the snippet stays the second check.
- Changing `has_words` or `cos_peer.py`.

## Calls I made

- ⚠ **The whole sentence counts, not just the words right before.** A negation word anywhere in the sentence, before or after the command, rejects it. So "approve 30, no rush" and "no problems, approve 30" are refused, and the user has to send a plain `approve 30`. The ticket asked for "directly before" plus "do not earlier in the sentence"; its own `not yet, approve 30 later` case needs `not` anywhere earlier, and failing closed on "after" too keeps the rule one line long.
- ⚠ **Line breaks don't end a sentence.** "Don't merge yet" on one line and "approve 30" on the next is refused. The matcher already folds line breaks away; keeping them would mean a second normalizer. A period, `!`, `?` or `;` does end it.
- ⚠ **It applies to every command, not only `approve N`.** "don't cancel 30" no longer counts as `cancel 30`, and "do not stop everything" no longer stops everything. That is the same fail-closed direction, but it changes `stop everything` too: a user who writes "no, stop everything" has to repeat it as "stop everything".
- ⚠ **The build stops once in the middle** for you to merge the upstream collective-wisdom PR on GitHub, because the installer only installs commits on upstream `main`. You get one `BLOCKED:` with the upstream PR link, then a normal `MERGE READY` for the install PR here.
- The newest matching message decides. A negated newest message fails even when an older plain `approve 30` exists, instead of falling back to it.
- If a message holds the words twice and either one is negated, the whole message is refused.
- Negated `latest` prints `not-user negated …` (reusing the `not-user` prefix callers already handle) instead of a new prefix. `item` prints `reject: words negated`.
- `don t` (a space instead of an apostrophe) is not caught; the list is the ticket's plus `nor`, `cannot`, `cant`, `wont` and any `n't` word.
- The upstream branch is named after this ticket (`feat/nh-35-…`), as NH-29 did upstream, not a new `CW-N` ticket.
