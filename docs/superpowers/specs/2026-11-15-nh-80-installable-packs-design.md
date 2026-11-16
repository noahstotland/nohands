# NH-80: Installable app packs: Design

**Date:** 2026-11-15  **Ticket:** [NH-80](https://github.com/noahstotland/nohands/issues/80)
**Status:** Shipped
**Shipped:** in PR #142, with differences: [as-built](../as-built/2026-11-15-nh-80-installable-packs.md)

## Intent

NH-76 built app packs into the app as Swift tables. This lets the user add voice commands for more apps by installing a pack file, without a new build. A pack is data, never code: installing or loading one cannot run anything, reach the network, or act outside its own apps.

Non-goals: fetching, browsing or updating packs from a server; signing; packs with code, scripts or a plugin API; the model calling pack actions in the task loop; a "Install Pack…" file picker in the menu bar.

Anti-goals: a pack phrase matching "stop", a mode phrase or a spoken release; a pack acting while none of its apps is frontmost; a pack typing text, clicking at points or calling the model; a close, quit or irreversible menu item behind a phrase that doesn't say so; a silent install; a bad pack file taking down the grammar.

## Decision

One JSON file per pack, parsed and validated by pure code in `NoHandsCore`, installed by `NoHandsMac` into `~/.config/nohands/packs/<id>/pack.json`. Built-in packs keep their Swift tables but gain an `id` and round-trip through the same format (a test), so there is one shape. Putting built-ins in bundled JSON resources was rejected: it adds a resource bundle to Core and runtime parse failures for code we ship.

## Pack file format (version 1)

```json
{
  "format": 1,
  "id": "bear-notes",
  "name": "Bear",
  "version": "1.0.0",
  "author": "Jane Doe",
  "bundleIDs": ["net.shinyfrog.bear"],
  "commands": [
    { "phrases": ["new note", "make a note"],
      "actions": [{ "kind": "press_key", "key": "n", "modifiers": ["command"] }] },
    { "phrases": ["archive note"], "actions": [{ "kind": "menu_item", "title": "Archive Note" }] },
    { "phrases": ["bear help"], "actions": [{ "kind": "open_url", "url": "https://bear.app/faq/" }] }
  ]
}
```

Action kinds (names match the intent schema): `press_key` (`key`, optional `modifiers`, same values as the decoder), `menu_item` (`title`), `open_app` (`app`), `open_url` (`url`, `https` only, a host, no user or password). Each maps to an existing `Action` case; nothing new reaches the executor.

### Validator (`PackFile.parse(_ data:)` in Core)

Returns the pack or one `PackError` (a reason with no file content, safe to log). Rejects:

- Over 64 KiB, invalid JSON, a missing or unknown key at any level, `format` other than 1.
- `id` not matching `^[a-z0-9][a-z0-9-]{1,39}$`, or equal to a built-in pack's id.
- `name`, `author` over 60 characters, `version` over 20, any control character; empty `bundleIDs`, over 16, or one not made of letters, digits, `.` and `-`.
- Over 200 commands, over 500 phrases, a phrase over 60 characters or 8 words, a phrase that normalizes to nothing, the same phrase twice after `CommandGrammar.normalize`, over 8 actions per command, an empty action list.
- An unknown action kind (including `type_text`, `click`, `set_mode`, `run_*` and every other schema kind), a bad key or modifier, a `menu_item` title over 100 characters, an `open_app` name over 60, a URL that isn't `https` or is over 2048 characters.
- A **reserved phrase**: a stop phrase (`StopWords.isStop`), or a phrase whose global table entry contains `.setMode`, `.releaseMouse` or `.hideOverlay` ("go to sleep", "wake up", "dictation mode", "stop dictating", "release click", "hide numbers", "cancel"…).
- A command blocked by `ShortcutGuard.blocked(actions, goal: phrase)` or held by `IrreversibleGuard.held(actions, labels: [:], goal: phrase)` for any of its phrases: "zap" cannot be command-Q, "tidy up" cannot be the "Empty Trash" menu item. "quit bear" can be command-Q.
- **Key and focus rules** (a pack cannot type, or act outside its app): over 2 `press_key` actions in a command with no command, control or option modifier; a `return` or `space` press with no command, control or option after a `menu_item`; an `open_app` or `open_url` that is not the command's last action; a chord of command-space, command-tab, command-option-escape, command-shift-delete or command-option-shift-delete unless the phrase has the words "empty" and "trash".
- **Loose menu titles**: menu items match by words at run time (`MenuMatch` prefix and contains tiers), so `IrreversibleGuard.namesLoosely(title:goal:)` also holds a `menu_item` title whose folded words are a part of a guarded verb's name ("empty" for "empty trash", "place" for "place order") when the phrase does not allow that verb.
- **`open_url` hosts**: an IP literal, `localhost`, a `.local` or `.localhost` name, or a host with no dot.

Any rejection skips the whole pack; the grammar and the other packs load as before.

### Summary (`PackSummary`)

What the user sees before saying yes: name, version, author, apps (bundle IDs), phrase count, `open_url` hosts, `open_app` names, global phrases it overrides in its apps (any phrase the global grammar parses without a pack, patterns like "press return" included), and phrases shadowed by packs already installed. When the id is already installed: "replaces version X".

## Lookup (`PackSet` in Core)

`CommandGrammar` today takes the first pack that claims the bundle ID. It now takes a `PackSet` built from an ordered list: built-in packs first, then enabled installed packs by install order. For each bundle ID it merges the phrase tables, first claim wins; a later pack's phrase that loses is **shadowed**, and `PackSet` lists those (pack id, phrase, winner). Lookup order in `parse` is otherwise NH-76's: a pack phrase still beats a global phrase in its own app, and a stop phrase never reaches a pack.

## Install and load (`PackStore` in NoHandsMac)

- Folder `~/.config/nohands/packs/` (700), one `<id>/` per pack (700) with `pack.json` (600). Folders and files are made, read and written with `ConfigFile`'s private-file steps: symlinks refused, temp file plus rename.
- **Install order** is the `<id>/` folder's creation time (ties by id). Re-adding an installed id replaces `pack.json` in place, so it keeps its order and on/off state.
- **Off** is an empty `disabled` file in the pack's folder. No config.json writes.
- **Load** reads each `<id>/pack.json` (no network), validates it, and skips a bad one with a logged reason. `pack list` and the menu show it as invalid.
- **Remove** deletes only `packs/<id>/`, after checking `id` against the id pattern and refusing a symlinked folder.
- **Limits on load**: at most 100 packs are listed or loaded (the first one past it is shown invalid, the rest ignored; install refuses a new id at 100), and `pack.json` is read up to 64 KiB + 1 byte. The app coalesces change notifications to one reload per 500 ms.
- **Reload**: after a change, `PackStore` posts the local distributed notification `com.nohands.packs-changed` (no payload). The app reloads on it and when the menu opens, and swaps the grammar's `PackSet` on the main actor; an utterance already being routed uses the old one.

## Entry points

- `nohands-cli pack add <file>`: validates, prints the summary, asks `Install? [y/N]` on stdin, and installs only on `y` or `yes`. No `--yes` flag.
- `nohands-cli pack list`: id, version, on/off, phrase count, and shadowed or invalid notes.
- `nohands-cli pack remove <id>`: removes it, no prompt.
- `nohands-cli pack builtin <id>`: prints a built-in pack as a pack file, as a template for authors.
- Menu bar **Packs** submenu: one item per pack ("Bear 1.0.0"), each with **On** (checkmark toggle), **Remove** (asks in an alert first) and a greyed line such as "12 phrases, 1 shadowed" or "invalid: unknown action kind". With none: "No packs installed".
- `docs/app-packs.md` documents the format, the limits and how to write a pack, linked from `README.md`; `docs/cli.md` gets the four `pack` rows. No voice phrases change, so `docs/voice-commands.md` only gains a line pointing to app packs.

## Tests

- Core, table-driven: the validator accepts a good pack and rejects each case above (unknown kind, `type_text`, `http` URL, oversize, duplicate phrase, bad id, invalid JSON, unknown key, reserved phrase, guard-blocked chord, irreversible menu title).
- Core: a pack phrase runs only while its bundle ID is frontmost; a pack can't claim "stop"; the first installed pack wins a clash and the second is listed as shadowed; built-in beats installed.
- Core: every built-in pack encodes to a pack file that parses back equal.
- Mac, temp directory: install writes 700 folders and a 600 file, refuses a symlinked folder or file, re-add keeps order, remove deletes only that pack's folder.
- `swift test` needs no network and no installed packs.
- Manual (in the PR): install a sample pack, say its phrase in the target app, check it does nothing in another app, toggle it off, remove it.

## Calls I made

- A pack whose command is close, quit or irreversible without saying so in its own phrase is rejected at validation, using the same guards as the task loop. The ticket only named `ShortcutGuard`; `IrreversibleGuard` is added for menu titles like "Empty Trash".
- One bad entry rejects the whole pack, not just that entry: the author sees one clear error, and a half-loaded pack never surprises the user.
- An installed pack may still override an ordinary global phrase inside its own apps (NH-76's rule), but never a stop, mode or release phrase. The install summary lists each override.
- Built-in packs win every clash with installed ones, and an installed id can't reuse a built-in id ("terminal").
- Install order comes from the folder's creation time and on/off from a `disabled` marker file, so there is no index file to keep in sync and no write to config.json.
- The app learns about CLI installs through a local distributed notification and on menu open; no file watcher.
- The CLI asks on stdin and has no `--yes`, so there is no silent install, even scripted. Piping `y` still works.
- The menu bar lists, toggles and removes packs but cannot install one; install is CLI only for now. Remove from the menu asks first; `pack remove` doesn't.
- Added a `format: 1` key and a `pack builtin <id>` command (not in the ticket) for future format changes and as an author template.
- `open_url` takes no app name; it opens in the default browser.
- The limits (64 KiB, 200 commands, 500 phrases, 8 words, 8 actions, 16 bundle IDs) are my picks, sized well above the Terminal pack (36 phrases).
- Pack docs live in a new `docs/app-packs.md`, since NH-119 moved reference material out of the README.
