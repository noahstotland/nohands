# NH-11: Start at Login and an Open config.json menu item — Plan

**Spec:** [2026-11-05-nh-11-start-at-login-design.md](../specs/2026-11-05-nh-11-start-at-login-design.md)
**Ticket:** NH-11

## Tasks

1. `Sources/NoHandsCore/LoginItemMenu.swift`: pure `LoginItemState` (`enabled`, `notRegistered`, `requiresApproval`, `notFound`) and `LoginItemMenu.item(for:)` returning title, checkmark (`on`, `off`, `mixed`), enabled and click action (`register`, `unregister`, `openSettings`, `none`), per the spec's status table. No ServiceManagement import.
2. `Tests/NoHandsCoreTests/LoginItemMenuTests.swift`: one table over the four states. Done when a `.requiresApproval` row asserts `openSettings`, not `register`.
3. `Sources/NoHandsMac/ConfigFile.swift`: `ConfigFile.defaultURL` and `ConfigFile.ensureExists(at:) throws -> Bool`. Directory mode 700; file created with `open(O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)` and `{}\n`; `EEXIST` returns false and touches nothing; other errno throws. No AppKit. `AppDelegate.loadConfig()` uses `ConfigFile.defaultURL`.
4. `Tests/NoHandsMacTests/ConfigFileTests.swift`: one table in a temp directory: missing dir and file (created, `{}\n`, mode 600, dir 700, true); existing 644 file with content (bytes and mode unchanged, false); symlink at the path, live and dangling (not followed, not replaced, false).
5. `Sources/NoHandsMac/LoginItem.swift`: `@MainActor` wrapper over `SMAppService.mainApp` (status mapped onto `LoginItemState`, `register`, `unregister`, `openSettings`).
6. `Sources/NoHands/AppDelegate.swift`: `Start at Login` and `Open config.json…` items in a group above Quit; the login item is re-read in `refresh()` and `menuWillOpen` (before the probe guard) and after each click, set from `LoginItemMenu.item(for:)` (state `.on/.off/.mixed`). A throwing register/unregister logs one `PipelineLog.warning` and shows the HUD notice `couldn't change Start at Login: allow NoHands in Login Items`. Open config: `ensureExists`, open with `NSWorkspace` (TextEdit when no app claims `.json`), HUD notice `restart NoHands to apply config changes` for 4 s; failure logs the path only and shows `couldn't create config.json: check ~/.config/nohands`.
7. Docs: `README.md` Start at Login paragraph and one Configuration sentence; add both items to the menu section of `docs/superpowers/specs/2026-11-04-nohands-design.md`.
8. Verify: `swift build` (no warnings from the new files) and `swift test` green. Manual checks are listed in the spec and go in the PR, not claimed as passed.
