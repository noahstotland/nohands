# As-built: Per-app voice commands

**Shipped:** in PR #129
**Ticket:** NH-76
**Spec:** [2026-11-15-nh-76-per-app-commands-design.md](../specs/2026-11-15-nh-76-per-app-commands-design.md)

## Differs from the spec

- The spec's walk budget names 200 ms / 1500 items; the reader is `@MainActor` and uses the item's index as its handle.
- If an app ignores `AXPress`, the executor falls back to agent-desktop when present, else fails with `couldn't press menu item <title>`.
- Matching folds apostrophes away and turns other punctuation into a space ("Back/Forward" stays two words).
- `parse` also skips packs for any stop phrase in code, on top of the test over `AppPacks.all`.
- `nohands-cli`'s existing menu-item failure texts changed to "menu item <title> is disabled" and "no menu item called <words>".
- `EndpointReplay` still parses with no bundle ID.
- Steps the model chose (the task loop) press only an item whose title equals the name sent, never a closest match, so the irreversible guard's check of the sent name holds ("trash" cannot press "Empty Trash…"). Only the user's own `menu <words>` uses the closest tiers.
- Items that only open a submenu are never matched (`menu find` runs `Find…`, not the `Find` submenu).
- The menu walk is breadth first: every top-level menu is read before any submenu.
- A model step must equal the menu title as written (case and a trailing "…" aside), checked by `MenuMatch.plain`, so characters the looser matching fold deletes cannot slip a name past the irreversible guard. The same check applies to agent-desktop's find result.
- `ShortcutGuard` now covers `menuItem`: a title with a close word or a quit word needs the goal to ask for it, like command-W and command-Q. (The spec listed this as a follow-up; the native loop now runs `menu_item`, so it ships here.)
- Apple menu titles (Shut Down, Restart, Log Out <name>, Sleep, Lock Screen, Force Quit, …) are refused on the agent-desktop fallback too, by the spoken name and by the item agent-desktop found.
