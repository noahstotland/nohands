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
- An unknown name after `open settings for` is rejected only when it is short. Filler words (`the`, `a`, `please`, `my`) are dropped, `&` reads as `and`, and a name with a compound word (`and`, `then`, `to`, `type`, ...) or of more than four words after fillers goes to the model instead, so `open settings for bluetooth and turn it off` still works as a task.
- `screenshot window` waits up to 1 s for the screenshot tool to start (a fixed 300 ms when it was already running) before pressing space, and fails with `the screenshot tool did not start` instead of typing a space into the front app.
- `mission control` and `show desktop` return `couldn't open Mission Control` or `couldn't show the desktop` when the app can't be opened.
