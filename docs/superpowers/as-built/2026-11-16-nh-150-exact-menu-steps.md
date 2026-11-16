# As-built: Press only the exact title for pack menu steps, and close two guard gaps

**Shipped:** in PR #173
**Ticket:** NH-150
**Spec:** [2026-11-16-nh-150-exact-menu-steps-design.md](../specs/2026-11-16-nh-150-exact-menu-steps-design.md)

## Differs from the spec

- The spec's § 3 checks the whole title; `MenuMatch.isLookalike` checks word by word, so an accented or CJK word beside a disguised one ("Sеnd Ägain", Cyrillic е) cannot hide it.
- Invisible characters (zero-width joiner, combining grapheme joiner and other default-ignorable scalars) are dropped first, so they cannot hide a lookalike letter.
- The spec says an all-table-letter word such as "со" is flagged. It is flagged only when the title has no real letter of the same script, so "О программе Safari" and "Σχετικά με το Safari" keep working. A genuine same-script letter elsewhere clears an all-lookalike word ("Сору Ж"); accepted.
