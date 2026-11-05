# NH-11: Start at Login and an Open config.json menu item — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-11](https://github.com/noahstotland/nohands/issues/11)
**Shipped:** in PR #25, as specified

## Intent

NoHands has to be started by hand after every login, and the only way to change a setting is to find
`~/.config/nohands/config.json` yourself. Two menu items fix that: a **Start at Login** checkbox and an
**Open config.json** item. No settings window, no live reload.

## Menu

The new items go in their own group just above Quit:

```
Listening
──────────
<transcript> / local model / harness
──────────
Pause Listening / Retry / Grant Accessibility… / Microphone…
──────────
Start at Login            ✓ when registered
Open config.json…
──────────
Quit NoHands
```

### Start at Login

- Backed by `SMAppService.mainApp` (ServiceManagement, macOS 13+; the floor is 14). Clicking it calls
  `register()` when off and `unregister()` when on.
- The checkmark is read from `SMAppService.mainApp.status` each time the menu opens and after each click,
  never cached in config or `UserDefaults`, so it is right after a relaunch and after the user removes the
  item in System Settings.
- Status → item:

  | `status` | Title | Checkmark | Enabled |
  |---|---|---|---|
  | `.enabled` | Start at Login | on | yes |
  | `.notRegistered` | Start at Login | off | yes |
  | `.requiresApproval` | Start at Login: allow in Login Items | mixed (–) | yes, opens Login Items settings |
  | `.notFound` | Start at Login: run the app from build/NoHands.app | off | no |

- `.requiresApproval` is what macOS returns when the user turned NoHands off under System Settings >
  General > Login Items, and can follow `register()`. Clicking the item then opens that pane
  (`SMAppService.openSystemSettingsLoginItems()`) instead of calling `register()` again.
- A `register()` / `unregister()` that throws: one `PipelineLog.warning` with the error, and the notice line
  shows `couldn't change Start at Login: allow NoHands in Login Items` (one line, names the next step). The
  menu then shows whatever `status` reports.
- `.notFound` covers `swift run NoHands` (no app bundle); the item is disabled with the hint instead of
  failing on click.

### Open config.json

- Title `Open config.json…`. On click:
  1. If `~/.config/nohands/` is missing, create it (mode 700).
  2. If `config.json` is missing, create it with `{}` and a trailing newline, mode 600, atomically and
     without following or replacing anything already there (`O_CREAT | O_EXCL`). An existing file is never
     rewritten, truncated or re-permissioned.
  3. Open it with `NSWorkspace.shared.open(url)` (the default app for `.json`). If no app claims `.json`,
     fall back to TextEdit.
  4. Show the notice `restart NoHands to apply config changes` for 4 s.
- If creating the file fails (e.g. a read-only home), log a warning with the path (never contents) and show
  `couldn't create config.json: check ~/.config/nohands`.

## Code layout

- `NoHandsCore/LoginItemMenu.swift`: a pure `LoginItemState` enum (`enabled`, `notRegistered`,
  `requiresApproval`, `notFound`) and `LoginItemMenu.item(for:)` → title, checkmark, enabled, click action
  (`register`, `unregister`, `openSettings`, `none`). No ServiceManagement import; the app maps
  `SMAppService.Status` onto it.
- `NoHandsMac/ConfigFile.swift`: `ConfigFile.defaultURL` (moved out of `AppDelegate.loadConfig()`, which then
  uses it) and `ConfigFile.ensureExists(at:) throws -> Bool` (true if it created the file). Plain
  `FileManager` / POSIX `open`, no AppKit.
- `NoHandsMac/LoginItem.swift`: thin `@MainActor` wrapper over `SMAppService.mainApp` (status mapping,
  register / unregister / open settings).
- `Sources/NoHands/AppDelegate.swift`: the two `NSMenuItem`s, refreshed in `refresh()` and `menuWillOpen`.

## Tests

- `LoginItemMenuTests` (Core, table-driven): each state → title, checkmark, enabled, action. This is the rule
  that a stuck `.requiresApproval` opens Settings rather than looping on `register()`.
- `ConfigFileTests` (Mac, temp directory, no permissions needed), one table over: missing dir + missing file →
  created, `{}`, mode 600, returns true; existing file with content and mode 644 → untouched bytes and mode,
  returns false; a symlink at the path → not followed, not replaced. Overwriting a user's config (and their
  API key) is the failure that would hurt.
- No test for `SMAppService` itself or the menu layout (framework behaviour and UI copy, per AGENTS.md).

## Docs

- `README.md`: a short **Start at Login** paragraph after the bundle/permissions section, and one sentence in
  Configuration that the menu's Open config.json creates the file with mode 600 and that changes apply after
  a restart.
- `docs/superpowers/specs/2026-11-04-nohands-design.md`: add the two items wherever it lists the menu.

## Manual checks (listed in the PR, not claimed as passed)

1. `scripts/bundle.sh && open build/NoHands.app`; tick Start at Login; log out and in → NoHands is running.
2. Quit and relaunch → the item still shows ticked. Untick, relaunch → unticked.
3. Turn NoHands off in System Settings > Login Items → the item shows `allow in Login Items` and opens that pane.
4. Move `config.json` aside; click Open config.json → the file exists with `{}`, `ls -l` shows `-rw-------`,
   it opens in the default editor, and the notice says to restart. Put the original back.
5. With an existing config.json → it opens unchanged (same contents, same mode).

## Leaves out

- Reloading config without a relaunch, a Restart menu item, a settings window (out of scope per ticket).
- Validating the JSON on open or after save.
- Any voice command for either item (no new phrase; the README voice table is unchanged).

## Calls I made

- **Requires-approval state opens System Settings** instead of re-calling `register()`, and shows a mixed
  checkmark. The ticket only says "reflecting the current registration state".
- **Running without a bundle disables the item** with a one-line hint, rather than erroring on click.
- **Ad-hoc signing is fine.** `bundle.sh` signs ad-hoc by default; `SMAppService.mainApp` works with that,
  but the login item is tied to the app's path and signature, so a rebuild may need re-ticking or re-approval
  (same as the existing Accessibility grant note). Noted in the README, no code change.
- **No change to the existing Accessibility/mic items or `CODESIGN_IDENTITY`.**
- **Never touch an existing config file**, not even to fix a too-open mode: the launch-time permissions
  warning already covers that.
- **Missing `~/.config/nohands/` is created with mode 700.**
- **TextEdit fallback** when no app is registered for `.json`.
- **Notice "restart NoHands to apply config changes"** after opening, as the ticket suggests, instead of a
  restart item.
- **Menu placement:** a new group just above Quit.
- **Pure state mapping in NoHandsCore, file creation in NoHandsMac** (FileManager/POSIX, not AppKit, but it
  is filesystem integration, so it stays out of Core).
