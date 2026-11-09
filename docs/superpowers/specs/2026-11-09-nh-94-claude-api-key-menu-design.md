# NH-94: Menu item to enter the Claude API key: Design

**Date:** 2026-11-09  **Ticket:** [NH-94](https://github.com/noahstotland/nohands/issues/94)
**Status:** Proposed

## Intent

For the bundled app, the only way to give NoHands a Claude key is to edit `~/.config/nohands/config.json` by hand, because
shell exports do not reach an app started with `open`. A menu item with a masked field replaces that, and the save keeps
the file's existing safety rules.

This is a small change: one pure function, one file write, one menu item.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals, from the ticket: changing the default model or effort (#39), the macOS Keychain, removing the key from the
menu, spend limits. Also not here: applying the key without a restart, and telling whether the key works (#103).

Anti-goals, which would make this a failure even if it works:

- Any part of the key in the menu, the HUD, an error message or the log. `PipelineLog`'s `detail` is private in the
  unified log but is printed unredacted to a terminal, so the key must not reach `detail` either.
- A save that loses or corrupts anything else in `config.json`.
- A key left readable by other users, or written through a symlink.
- A field the user cannot paste into.

## What the code forces

- **Cmd-V won't work unless we add it.** The app runs with `.accessory` policy and never sets `NSApp.mainMenu`. Text
  fields get Cmd-V, Cmd-C, Cmd-X and Cmd-A through the main menu's key equivalents, so without one a paste does nothing.
  Since pasting is the whole feature, this has to be solved here (see [Alert](#alert)).
- **The alert must activate the app first.** An `.accessory` app is not frontmost when a menu item is chosen, so without
  `NSApp.activate` the alert can open behind other windows and the field does not get typing focus.
- **Foundation's JSON parse errors can quote the input,** so the parse error is dropped, not logged.
- **`AppConfig` can't do the merge.** Decoding and re-encoding it would drop unknown keys and write every default into
  the file.

## Approaches

1. **Parse with `JSONSerialization`, set the key, write it back (chosen).** About 15 lines of pure code. Every key and
   value is kept, but key order and spacing are not: the file comes back sorted and pretty-printed.
2. **Splice the new value into the original text.** Keeps the user's formatting byte for byte, but needs a small JSON
   scanner to find the value's span, and a bug there writes a broken config. That is a poor trade for cosmetic gain.
3. **Decode and re-encode `AppConfig`.** Ruled out above.

## How it works

### Merge (`ClaudeKeyEntry`, NoHandsCore, Foundation only)

- `normalized(_ text: String) -> String?` trims whitespace and newlines, and returns nil when nothing is left.
- `merged(existing: Data?, key: String) throws -> Data` treats nil as `{}`, parses the data, sets `anthropicAPIKey`, and
  serializes with `.prettyPrinted`, `.sortedKeys` and `.withoutEscapingSlashes` plus a trailing newline.
- Anything that doesn't parse to a JSON object throws `invalidJSON`, which carries no payload. That includes an empty
  file and valid JSON that isn't an object (`[]`), the same files `AppConfig.load` already flags as invalid.

### Write (`ConfigFile.saveAnthropicKey(_:at:)`, NoHandsMac)

In order, stopping at the first failure with nothing changed:

1. Create `~/.config` if missing. Create the `nohands` folder with mode 700 if missing. If it exists, `lstat` it: a
   symlink or non-directory is refused, and a real folder is set to 700.
2. Open `config.json` with `O_RDONLY | O_NOFOLLOW | O_NONBLOCK`. Missing means no existing data. A symlink is refused
   (`.symlink`), and so is anything that is not a regular file.
3. Call `merged`. `invalidJSON` passes through and the file stays as it was.
4. Write to a `mkstemp` file in the same folder (always mode 600), `fsync`, close, then `rename` over `config.json`. The
   rename replaces the file itself, so the result is mode 600 even when the old file was wider, and a symlink that
   appears after step 2 is replaced, not followed.
5. On any failure after step 4 starts, unlink the temp file, since it holds the key.

Errors are an enum with no text from the file or the key: `.invalidJSON`, `.symlink`, `.writeFailed(POSIXErrorCode)`.

### Alert

- `NSAlert` with a `NSSecureTextField` as its accessory view, Save and Cancel buttons, and the field as first responder,
  shown with `runModal` after `NSApp.activate`. The field is always empty: the saved key is never loaded into it.
- Informative text, short: `Applies after you restart NoHands. ANTHROPIC_API_KEY, if set, overrides this.`
- Editing shortcuts: the app sets a `NSApp.mainMenu` holding only an Edit menu with Cut, Copy, Paste and Select All. An
  `.accessory` app never shows a main menu, so nothing visible changes, and those selectors go down the responder chain to
  the field.
- Empty after trimming: no write and no message.

### Menu (`AppDelegate`)

- `claudeKeyItem` goes directly before `openConfigItem`. Titles: `Set Claude API key…` and `Change Claude API key…`.
- The title comes from `fileHasKey`, set in `loadConfig` from the existing no-environment load and set true after a save.
  It reflects the file, so a key that exists only in `ANTHROPIC_API_KEY` still reads `Set`.
- A save does not change `config` in memory, matching "applies after a restart".

| Result | HUD |
|---|---|
| Saved | `Claude key saved: restart NoHands to apply` |
| Invalid JSON | `couldn't save key: fix config.json, then try again` |
| Symlink | `couldn't save key: replace the config.json link with a file` |
| Write failed | `couldn't save key: check ~/.config/nohands` |

`PipelineLog` gets a fixed message, plus the errno name for a write failure and nothing else.

### Text and docs

- `PipelineText.llmOff` becomes `LLM off: choose Set Claude API key… in the menu`, and its assertion in
  `PipelineTextTests` follows.
- `README.md`: the "Claude API key" paragraph and § Configuration describe the menu item. "An existing file is never
  changed" stays, now scoped to Open config.json….

### Fitting with NH-103

NH-103 adds `claudeItem` and `checkClaudeItem` after `harnessItem`, and a key source on `AppConfig.load`. This ticket
touches neither. The menu-array and `item.target` lines in `buildMenu` are the expected rebase conflict, and the resolution
is to keep both. NH-103's status line reads the running config, so after a save and before a restart it correctly still
says what is in use. Its `check anthropicAPIKey` wording can stay.

## Tests

- One table-driven test in NoHandsCore for `merged`: no file, `{}`, other keys, existing key replaced, invalid JSON, `[]`,
  empty file, a key with quotes and backslashes. It parses the output and compares other values with their types, and
  loads it through `AppConfig.load` to confirm the key reads back exactly.
- `normalized` in the same file: surrounding spaces and newlines, empty, whitespace only.
- One table-driven test in `ConfigFileTests`, in a temp folder: fresh save (600 and 700), a 644 file and 755 folder
  tightened, a symlink at the file refused with the target untouched, a symlinked folder refused, invalid JSON left byte
  for byte, and no temp files left behind in any case.

Manual checks, listed in the PR:

- Cmd-V pastes into the field, the alert opens in front, and the characters are masked.
- After a save and a restart, a natural-language command reaches Claude without "LLM off". NH-103's follow-up says Claude
  requests currently return HTTP 400 for a schema reason, so "reaches Claude" is the bar here, not "command succeeds".
- `log stream` output and the menu titles after a save show no part of the key.

## Left to the builder

- Exact helper names and file placement beyond those above, and the temp file's name prefix.
- Wording tweaks that stay on one line and keep the next step.

## Calls I made

1. **A save rewrites `config.json` sorted and pretty-printed.** Every key and value is kept, but a hand-arranged order
   and spacing are not. Keeping the bytes needs a custom JSON scanner, which is a worse risk for a file that holds the
   app's settings.
2. **A symlinked `~/.config/nohands` folder is refused too,** like a symlinked file. The ticket only names the file. If
   you keep this config in a dotfiles repo through symlinks, the menu item won't work for you and you would edit the file
   by hand as today.
3. **The app gains a hidden Edit menu.** The ticket doesn't mention it, but without it paste does nothing in this app.
4. **The menu title reflects the file as of launch plus saves from the menu.** A hand edit shows up after a restart, like
   every other config change.
5. **No check that the text looks like a key,** such as an `sk-ant-` prefix. A format rule can go stale, and NH-103's
   check answers whether it works.
6. **An empty or whitespace-only `config.json` is refused as invalid,** not treated as `{}`, because `AppConfig.load`
   already flags it as invalid.
7. **A folder that exists with wider permissions is tightened to 700.** The ticket's rule is "folder mode 700", while
   `ensureExists` leaves an existing folder alone. `Open config.json…` keeps its behavior.
8. **Results show in the HUD, not a second alert,** matching `Open config.json…`.
