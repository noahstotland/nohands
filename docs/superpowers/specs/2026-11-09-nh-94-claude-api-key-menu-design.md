# NH-94: Menu item to enter the Claude API key: Design

**Date:** 2026-11-09  **Ticket:** [NH-94](https://github.com/noahstotland/nohands/issues/94)
**Status:** Shipped
**Shipped:** in PR #107, with differences: [as-built](../as-built/2026-11-09-nh-94-claude-api-key-menu.md)

## Intent

For the bundled app, the only way to give NoHands a Claude key is to edit `~/.config/nohands/config.json` by hand, because shell exports do not reach an app started with `open`. A menu item with a masked field replaces that, and the save keeps the file's safety rules.

Non-goals: model or effort (#39), the Keychain, spend limits, applying without a restart, testing the key (#103).

Anti-goals: any part of the key in the menu, HUD, error or log (`PipelineLog`'s `detail` prints unredacted to a terminal); a save that loses or corrupts other `config.json` content; a key readable by other users or written through a symlink; a field the user cannot paste into.

## What the code forces

- The app is `.accessory` with no main menu, so Cmd-V does nothing. It gets a hidden menu holding only Edit.
- The alert must `NSApp.activate` first, or it opens behind other windows.
- `AppConfig` can't do the merge: re-encoding drops unknown keys and writes every default. So parse with `JSONSerialization` and write back; every key is kept, order and spacing are not.

## How it works

- **Merge** (`ClaudeKeyEntry`, NoHandsCore): trims the input (empty means no write), sets `anthropicAPIKey` in the parsed object. Anything that isn't a JSON object, including an empty file, throws `invalidJSON` with no payload.
- **Write** (`ConfigFile.saveAnthropicKey`), stopping at the first failure with nothing changed: create `~/.config/nohands` as 700 (a symlink or non-directory is refused, a wider folder is set to 700); open `config.json` with `O_NOFOLLOW` (a symlink or non-regular file is refused); merge; write a `mkstemp` file (600) in the same folder, `fsync`, `rename` over `config.json`; on failure unlink the temp file. Errors carry no file or key text, since Foundation parse errors can quote input.
- **Alert:** a secure field that starts empty (the saved key is never loaded), with a note that it applies after restart and `ANTHROPIC_API_KEY` overrides it.
- **Menu:** `claudeKeyItem` before `openConfigItem`, titled `Set Claude API key…` or `Change Claude API key…` by whether the file has a key (so a key only in the environment reads `Set`). A save does not change `config` in memory.
- **Results** show in the HUD: saved (restart to apply), invalid JSON, symlink, write failed. `PipelineLog` gets a fixed message plus the errno name only.
- `PipelineText.llmOff` and `README.md` point to the item.

## Tests

- Table-driven: `merged` (missing, empty, non-object, odd characters, other keys kept) and `ConfigFile` in a temp folder (modes tightened, symlinks refused untouched, invalid JSON left byte for byte, no temp files left).
- Manual: paste works and logs show no key.

## Calls I made

1. **A save rewrites `config.json` sorted and pretty-printed.** A custom scanner is the worse risk.
2. **A symlinked `~/.config/nohands` is refused too.** Dotfiles-repo users edit by hand.
3. **No check that the text looks like a key.** Formats go stale; NH-103 checks that it works.
4. **An empty `config.json` is refused as invalid**, not treated as `{}`.
5. **An existing wider folder is tightened to 700.**
6. **Results go to the HUD, not a second alert.**
