# NH-35: Make cos_user_check.py reject a negated approval — Design

**Date:** 2026-11-05
**Status:** Shipped
**Ticket:** [NH-35](https://github.com/noahstotland/nohands/issues/35)
**Shipped:** in PR #64, with differences: [as-built](../as-built/2026-11-05-nh-35-reject-negated-approval.md)

## Goal

"do not approve 30 yet" must not count as the user's `approve 30`. `scripts/cos_user_check.py` (`latest` and `item`) fails closed when the command's words are negated in the user's message, and still passes a plain `approve N`.

## Today

`latest` takes the newest user message containing the words (`has_words`) and ignores the words around the match, so "don't approve 30" passes and could start a merge. It serves every Chief of Staff command. `cos_peer.py` imports `has_words` and must not change.

## Design

All code changes are upstream in collective-wisdom (`cos_user_check.py` and its test); this repo gets them through an install PR.

### The rule

A match is **negated** when the same sentence holds a negation word outside the matched words, before or after them.

- **Sentence:** normalized text cut at `.`, `!`, `?` or `;` followed by whitespace or the end. A period inside a token (`v0.3`) and line breaks do not cut.
- **Negation word:** `no`, `not`, `never`, `nor`, `cannot`, `dont`, `cant`, `wont`, or any token ending in `n't` (curly apostrophes mapped to `'`).
- Words inside the match are ignored, so `cross-repo.md`'s whole-message check works. If any occurrence is negated, the message is.

A helper `command_in(words, text)` returns `None`, `"negated"` or `"ok"`.

### Output

- `latest` picks the newest user message containing the words, with no fallback to an older one. A negated one prints `not-user negated <itemId> <first 80 characters>` and exits 1.
- `item` prints `reject: words negated` and exits 1.

### Tests and delivery

- One table in `test_cos.py` through both `latest` and `item`: plain forms pass (including "no. approve 30", its own sentence); negations before or after fail, curly apostrophe included. A newer negated message fails with no fallback.
- The upstream PR merges first, since `install.sh --update --to` only takes an upstream `main` commit; the build stops with `BLOCKED` until you merge it. Then an install PR here. No Swift files change.

## Non-goals

An approval record in `merge_pr.py`; intent beyond negation ("wait", sarcasm and conditionals still pass; the Chief of Staff's own read is the second check).

## Calls I made

- ⚠ The whole sentence counts, before or after. "approve 30, no rush" is refused and the user sends a plain `approve 30`.
- ⚠ It applies to every command: "do not stop everything" no longer stops everything.
- The newest matching message decides. `latest` reuses the `not-user` prefix. `don t` is not caught.
