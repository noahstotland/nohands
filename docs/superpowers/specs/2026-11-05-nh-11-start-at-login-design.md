# NH-11: Start at Login and an Open config.json menu item — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-11](https://github.com/noahstotland/nohands/issues/11)
**Shipped:** in PR #25, as specified

## Intent

Two menu items above Quit, replacing hand starts and hunting for `~/.config/nohands/config.json`: **Start at Login** and **Open config.json**. No settings window, no live reload.

## Start at Login

- Backed by `SMAppService.mainApp`. Clicking calls `register()` when off and `unregister()` when on.
- The checkmark is read from `status` when the menu opens and after each click, never cached.
- `.requiresApproval` (the user turned NoHands off under Login Items) shows "Start at Login: allow in Login Items" with a mixed mark. Clicking opens that Settings pane instead of calling `register()` again.
- `.notFound` with no app bundle (`swift run NoHands`) disables the item with the hint "run the app from build/NoHands.app".
- A throwing `register()` / `unregister()` logs a warning and shows `couldn't change Start at Login: allow NoHands in Login Items`.

## Open config.json

1. Create `~/.config/nohands/` (mode 700) if missing.
2. If `config.json` is missing, create it with `{}` and a newline, mode 600, atomically and without following or replacing anything there (`O_CREAT | O_EXCL`). An existing file is never rewritten, truncated or re-permissioned.
3. Open it with `NSWorkspace.shared.open` (TextEdit if no app claims `.json`).
4. Show the notice `restart NoHands to apply config changes` for 4 s.

If creating fails, log the path and error (never contents) and show `couldn't create config.json: check ~/.config/nohands`.

## Tests

Core, table-driven: each login state gives its title, checkmark, enabled and action. Mac, temp directory: a missing file is created `{}` at mode 600; an existing file keeps its bytes and mode; a symlink is not followed. Overwriting a user's config and API key is the failure that would hurt.

## Leaves out

- Config reload, a Restart item, a settings window, JSON validation, voice commands for either item.

## Calls I made

- Ad-hoc signing works, but the login item is tied to the app's path and signature, so a rebuild may need re-ticking.
- An existing config file is never touched, not even to fix a too-open mode.
- A restart notice, not a restart item.
