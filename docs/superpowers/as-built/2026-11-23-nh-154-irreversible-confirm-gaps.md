# As-built: Close the gaps left in the confirm for irreversible task steps

**Shipped:** in PR #184
**Ticket:** NH-154
**Spec:** [2026-11-23-nh-154-irreversible-confirm-gaps-design.md](../specs/2026-11-23-nh-154-irreversible-confirm-gaps-design.md)

## Differs from the spec

- A focused element on Return or Space counts only when it is a button, pop-up button, menu button or link (`AXQuery.focusedElementTitle`); a focused text field never blocks the key. The spec said "the focused element".
- The press-time hit test climbs at most 4 ancestors and stops at a window, application, sheet, web area, drawer or scroll area, so a container title cannot refuse a press.
- A drag is checked before the button goes down, not at the release (a refusal at the release would have run the press through `releaseAll`).
- The press-time check also covers `click_in` and the agent-desktop menu click, by the title the harness found.
- After a yes, the re-read is not wrapped in the cancellable runner: a spoken stop during it is honoured right after, before anything runs.
- The confirmed set is the verbs of the held string (split on " and "); a grid cell under a grid overlay is not a label for the "same labels" comparison.
- A past form ("sent") before a comma counts as a guarded verb form when deciding whether the comma ends a negation.
