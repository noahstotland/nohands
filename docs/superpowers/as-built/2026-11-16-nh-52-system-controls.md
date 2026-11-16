# As-built: System controls by voice

**Shipped:** in PR #161
**Ticket:** NH-52
**Spec:** [2026-11-16-nh-52-system-controls-design.md](../specs/2026-11-16-nh-52-system-controls-design.md)

## Differs from the spec

- The spec gives the rejection line only for an unknown pane. A bare `open settings for` also gets one: `say open settings for and a pane, like bluetooth`.
- Empty trash matches Finder's menu item by exact title (`Empty Trash…` or `Empty Trash...`) instead of `pressMenuItem`. A plain `Empty Trash` (the item that does not ask) is refused with the warning-off line.
- The menu-bar clock is looked up in both Control Center and SystemUIServer menu extras.
- Pane URLs open with System Settings named as the app, so another handler can't take them.
- Packs cannot express `.system`, so `isReservedGlobal` is unchanged.
