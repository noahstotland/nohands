# As-built: NH-35 reject a negated approval

**Shipped:** in PR #64 (upstream collective-wisdom PR #124, installed at `f49afcc`)
**Ticket:** NH-35
**Spec:** [2026-11-05-nh-35-reject-negated-approval-design.md](../specs/2026-11-05-nh-35-reject-negated-approval-design.md)

## Differs from the spec

- The spec applies the negation rule to every command `latest` serves, and says "no, stop everything" no longer stops everything. What shipped: the script rule is unchanged, but `chief-of-staff/SKILL.md` keeps the strict check only for `approve N`, `cancel N` and `resume`. For `changes N`, answers to a blocked ticket, `hold N`, `stop everything` and ticket requests the Chief of Staff passes the user's whole message as the words, and a whole-message match ignores its own negation. Without that, "changes 30: don't rename the file" and "hold 30, don't merge yet" were refused, and the hold would not have held.
- The spec says a sentence ends only at `.`, `!`, `?` or `;`. Now an ellipsis does not end one, and a negation word that starts the next sentence also negates ("Approve 30? No, not yet.").
- The spec lists `no`, `not`, `never`, `nor`, `cannot`, `dont`, `cant`, `wont` and any `n't` word. Also caught: `didnt`, `doesnt`, `isnt`, `arent`, `wasnt`, `werent`, `shouldnt`, `wouldnt`, `couldnt`, `havent`, `hasnt`, `hadnt`, `mustnt`, and the look-alike apostrophes U+2032, U+00B4, backtick, U+201B and U+02B9.
- `chief-of-staff/SKILL.md` gained more than one sentence: what `not-user negated` means, telling the user to resend the command, a quoted heredoc for the words, and a note that the exit 2 thread-read fallback does not run a negated approve, cancel or resume.
- The build did not stop at the install: the upstream PR was merged by the user first, as the spec's Delivery section planned.
