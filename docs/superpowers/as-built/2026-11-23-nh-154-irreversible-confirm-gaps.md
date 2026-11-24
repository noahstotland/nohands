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
- The press-time hit test prefers the nearest button, link, menu item, check box or radio button above what was hit (an icon inside "Send" does not hide it); the first title seen is the fallback.
- While number badges are showing, the re-read after a yes returns the badge map, so only the press-time check protects that step.
- The `clickCentre` fallbacks of `set_value`, `type_into`, `clear`, `set_checked`, `set_expanded` and `focus` have no press-time check; the before-step check covers them by name or label.
- Pack phrases go through `held` too: a pack step that drags onto an element named with a guarded verb, and a phrase with the new comma rule, are now checked the new way (both on the safe side).
- A same-titled, same-role label that moved to another row during the wait counts as unchanged (a list of per-row "Delete" buttons can still shift under a yes).
