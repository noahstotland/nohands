# As-built: Text editing by voice

**Shipped:** in PR #136
**Ticket:** NH-54
**Spec:** [2026-11-15-nh-54-text-editing-design.md](../specs/2026-11-15-nh-54-text-editing-design.md)

## Differs from the spec

- The spec's `TextRange` type shipped as `TextSpan` (name clash with Foundation).
- A phrase is looked up as spoken, then without a leading the/a/an/my. With a selection, a match before the selection wins, then after it, and a match inside it is the last resort.
- In dictation, a phrase edit in a field that is unreadable or won't take a range types the dictated words instead of failing, so a sentence starting "delete…" is not lost in Google Docs. Command mode fails as specified.
- The pipeline asks whether a text field is focused (one off-main Accessibility call) only for utterances shaped like an edit.
- An apostrophe counts as part of a word only between letters or digits.
- Password fields never count as a text field.
