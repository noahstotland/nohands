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
