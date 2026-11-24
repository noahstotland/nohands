# As-built: Resolve an ordinal click target like "first video"

**Shipped:** in PR #121
**Ticket:** NH-93
**Spec:** [2026-11-15-nh-93-ordinal-click-target-design.md](../specs/2026-11-15-nh-93-ordinal-click-target-design.md)

## Differs from the spec

- **Resolution order.** The spec tries `find(named:)` first and reads the name as a position only on a miss. As built,
  `TargetResolver.element` tries an exact title first, then the position, then the looser prefix and contains title
  match. A video titled "Reacting to my first video" therefore cannot take over "first video". `ActionExecutor` also
  guards on an exact title only.
- **Repeated titles.** The spec drops a title equal to the previous candidate's. As built, each result title counts once
  anywhere in the list, so grids (thumbnails in one row, titles in the next) work too.
- **New helper.** `LabelAssigner.find(exactly:)` (exact, case-insensitive title match) is new.
