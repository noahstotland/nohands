# NH-94: Claude API key menu item: Plan

Spec: [2026-11-09-nh-94-claude-api-key-menu-design.md](../specs/2026-11-09-nh-94-claude-api-key-menu-design.md). Branch `feat/nh-94-claude-api-key-menu`, rebased on main after NH-103 (#105), which already added `claudeItem` and `checkClaudeItem` after `harnessItem` in `Sources/NoHands/AppDelegate.swift`. Keep them.

Verify after every task: `swift build` clean. After tasks 1 and 2 also `swift test`.

## Task 1: pure merge (NoHandsCore)

- `Sources/NoHandsCore/ClaudeKeyEntry.swift`: `normalized(_:) -> String?` and `merged(existing: Data?, key: String) throws -> Data` with `ClaudeKeyEntry.Error.invalidJSON` (no payload), as the spec's Merge section says (`JSONSerialization`, `.prettyPrinted`, `.sortedKeys`, `.withoutEscapingSlashes`, trailing newline; nil existing is `{}`; empty data, `[]` or any non-object throws).
- `Tests/NoHandsCoreTests/ClaudeKeyEntryTests.swift`: a table for `merged` (no file, `{}`, other keys with types kept, key replaced, invalid JSON, `[]`, empty file, key with quotes and backslashes, read back through `AppConfig.load`) and a small table for `normalized`.

## Task 2: file write (NoHandsMac)

- `ConfigFile.saveAnthropicKey(_ key: String, at url: URL) throws` in `Sources/NoHandsMac/ConfigFile.swift`, with the steps in the spec's Write section: folder lstat and 700, `O_NOFOLLOW | O_NONBLOCK` read of a regular file, `mkstemp` in the same folder, `fsync`, `rename`, unlink the temp on failure. Errors: `.invalidJSON`, `.symlink`, `.writeFailed(POSIXErrorCode)`, with no text from the file or key.
- One table in `Tests/NoHandsMacTests/ConfigFileTests.swift` in a temp folder: fresh save (600, 700); a 644 file and 755 folder tightened; symlinked file refused with the target untouched; symlinked folder refused; invalid JSON left byte for byte; no temp files left in any case. The key text must not appear in any thrown error's description.

## Task 3: menu, alert, text, README (NoHands, NoHandsMac)

- `AppDelegate`: `claudeKeyItem` (target self) directly before `openConfigItem`; `fileHasKey` set in `loadConfig` (file only, `environment: [:]`) and after a save; title `Set Claude API key…` or `Change Claude API key…`, updated in `refresh()`.
- `@objc setClaudeKey()`: `NSApp.activate`, `NSAlert` with an `NSSecureTextField` accessory, Save and Cancel, informative text `Applies after you restart NoHands. ANTHROPIC_API_KEY, if set, overrides this.`, `runModal`, `normalized` (empty: return), `saveAnthropicKey`, then the HUD from the spec's table. `PipelineLog` gets fixed text only (plus the errno name for a write failure); never the key or an `\(error)` interpolation of anything holding it.
- Hidden Edit menu (Cut, Copy, Paste, Select All) set as `NSApp.mainMenu` in `buildMenu`, so Cmd-V reaches the field.
- `PipelineText.llmOff` becomes `LLM off: choose Set Claude API key… in the menu`; update `PipelineTextTests`. If the NH-103 status line text mentions editing `anthropicAPIKey` for a missing key, leave it.
- README: the "Claude API key" paragraph and § Configuration, scoping "an existing file is never changed" to Open config.json….
- No test for the alert or menu (AGENTS.md § Testing).

## Manual checks (PR body)

Cmd-V pastes into a masked field and the alert opens in front; after a save and restart a natural-language command reaches Claude without "LLM off"; `log stream` and the menu titles show no part of the key.
