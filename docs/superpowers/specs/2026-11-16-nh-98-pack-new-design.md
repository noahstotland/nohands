# NH-98: Create a new app pack from the app in front

**Date:** 2026-11-16
**Status:** Draft
**Ticket:** [NH-98](https://github.com/noahstotland/nohands/issues/98)

## Goal

Writing an app pack (NH-80) by hand means listing an app's menu titles and shortcuts yourself. `nohands-cli pack new` reads them from the app's menu bar and writes a draft pack file you edit and then install with `pack add`. The draft passes the NH-80 validator as written. It goes through the same validator and the same `Install? [y/N]` summary as any other file, so a generated pack gets no extra trust.

## What exists

- `AXMenuReader` (`Sources/NoHandsMac/AXMenuReader.swift`) already walks every menu of the frontmost app for `menu <words>`, within 200 ms and 1500 items. It reads title, path, enabled and "has submenu", not the keyboard shortcut. The ticket's note that only the menu bar items can be read is out of date.
- `MenuEntry` (`Sources/NoHandsCore/MenuMatch.swift`) holds those fields.
- `PackFile.parse` is the validator; `PackFile.encode` writes a pack as a file; `PackSummary` finds phrases the global grammar already parses. Built-in pack ids today: `terminal`, `vscode`, `mail`, `messages` (`AppPacks.all`).

## The command

```bash
swift run nohands-cli pack new                     # waits 3 s, then reads the app in front
swift run nohands-cli pack new --app Safari        # a running app, by name or bundle ID
swift run nohands-cli pack new --app Safari --out ~/safari.json
```

- Without `--app` it waits 3 s, as `menu --list` does, so you can bring the app forward.
- `--app` takes a running app's name (case-insensitive) or bundle ID. It reads that app's menu bar without bringing it to the front.
- `--out` names the file. The default is `<id>.json` in the current folder. An existing file is never overwritten: the command stops and says `<path> exists; pass --out with a new name`.
- It writes the file (mode 0644), prints the path, the counts, every menu item it left out with the reason, and the next step: `Edit it, then install with: swift run nohands-cli pack add <path>`. It does not install.
- Every string printed from the app (titles, app name) goes through `PackSummary.printable`, so a menu title cannot inject terminal escapes.

Errors, each naming what to do:

| Case | Message |
|---|---|
| Accessibility not granted | `Accessibility permission is not granted to this process (or its terminal).` (as `menu`) |
| `--app` names no running app | `no running app called <name>; open it first` |
| App has no menu bar, or no readable items | `<App> has no menu bar to read; open a window of it and try again` |
| App has no bundle ID, or one the validator rejects | `<App> has no usable bundle ID; write its pack by hand` |
| Every entry was left out | `nothing to put in a pack: every menu item of <App> was left out` plus the list; no file |

## The draft

`PackDraft.make(appName:bundleID:entries:)` in `NoHandsCore` returns the pack and the left-out list. Pure, table tested.

- `format` 1, `name` the app's name (cut to 60 characters), `version` `1.0.0`, `author` empty, `bundleIDs` the one app.
- **`id`**: the bundle ID lowercased, every character other than a letter or digit turned into `-`, runs of `-` collapsed, cut to 40 characters, trailing `-` dropped: `com.apple.Safari` is `com-apple-safari`. Built-in ids are short words with no dots, so this form does not collide with them, nor with ids NH-79/81/82/83 or the NH-85 registry are likely to pick. If it still equals a built-in id (`AppPacks.all`), `-custom` is appended. Shorter than 2 characters: `app-` is prepended.
- **One command per menu item, one phrase per command.** Items come from the top-level menus only (one level in: `File > Save`, not `File > Open Recent > report.txt`); the Apple menu is skipped, as in `AXMenuReader`.
- **Phrase**: the title lowercased, `…` and `...` removed, any character other than a letter, digit, apostrophe or space turned into a space, spaces collapsed. `Save As…` is `save as`, `Zoom In (+)` is `zoom in`.
- **Action**: an item with a shortcut the format can express becomes `press_key` with that chord. Any other item becomes `menu_item` with the title `<Menu> > <Title>` (`File > Export as PDF…`), so it presses that exact item at run time.
- **Shortcut mapping** (`MenuShortcut.chord`, pure): the AX command character (`kAXMenuItemCmdChar`) maps a letter, digit or listed punctuation to its `Key`; with no character, the virtual key (`kAXMenuItemCmdVirtualKey`) maps return, tab, space, delete, forward delete, escape, arrows, home, end, page up/down and F1 to F12 (the reverse of `Key.keyCode`). The modifier mask (`kAXMenuItemCmdModifiers`) adds shift (1), option (2), control (4), and command unless bit 8 ("no command") is set. An upper-case character does not imply shift. Anything else (a glyph-only shortcut, an unknown key) gives no chord, so the item becomes a `menu_item`.

### What it leaves out

Each left-out item is listed as `File > Close All: <reason>`. Checked in this order, first reason wins:

| Reason | Why |
|---|---|
| `disabled` | Disabled at the time of reading (the ticket's rule). The printout says to open a window with content and run again to catch more |
| `opens a submenu` | Pressing it does nothing |
| `no title` / `title has >` | Nothing to say, or the title would read as a menu path |
| `no words to say` / `too long to say` | Empty phrase, or over 60 characters or 8 words (the validator's limits) |
| `same phrase as <earlier item>` | Two items with the same phrase: the first in menu order stays |
| `already a NoHands phrase` | The grammar, with the built-in packs, already parses the phrase (as spoken or with its `open`/`go to`/`the` lead dropped) for this app: `copy`, `paste`, `new tab`. The pack would only repeat it, and `pack add` would list it as replaced |
| `irreversible` | `IrreversibleGuard.held` flags the action with an empty goal: Empty Trash, Delete…, Send, Place Order and the rest of its verbs. The validator would allow these, since the phrase is the title and names the verb, but a generated draft never holds an irreversible command the user did not write. Add one by hand if you want it |
| `rejected: <validator reason>` | The command alone fails `PackFile.parse`: a reserved phrase (`stop`, `cancel`, `hide numbers`…), a blocked chord (command-space, command-tab, command-option-escape, command-option-delete), a close or quit chord the phrase does not name, a loose irreversible title |
| `over the 200 command limit` | Past the validator's cap, in menu order |

Close and quit items whose phrase names the action (`close window` with command-W, `quit safari` with command-Q) pass the validator and stay in the draft. Each candidate command is checked by running `PackFile.parse` on a one-command pack, so the generator never restates a validator rule: the reasons above come from the validator itself. The whole draft is parsed once more before writing; if that fails (it should not), nothing is written and the reason is printed.

The file is written with `PackFile.encode`, so commands come out sorted by phrase.

## The menu reader

`MenuShortcutReader` in `NoHandsMac` reads one app's menus for `pack new`. It is separate from `AXMenuReader`, so the run-time `menu` walk, its budget and what the task loop sees do not change.

- It reads through a small `MenuNode` protocol (title, enabled, children, command character, virtual key, modifier mask), with an AX implementation that uses `AXQuery`'s calls on the app's `kAXMenuBarAttribute`. Tests use a fake tree.
- It returns `[MenuEntry]` for top-level menu items, one level in, with the new optional `shortcut: KeyChord?` field on `MenuEntry` (default nil, so every current caller is unchanged). Budget 2 s and 1500 items, since it runs once by hand.
- An app with no menu bar, or a bar with no menus past the Apple menu, throws `noMenuBar`, which the CLI turns into the message above.

## Tests

Per `AGENTS.md` § Testing, one table per rule:

- `PackDraftTests` (core): a table of menu entries to the expected draft: shortcut to chord, no shortcut to `menu_item` with the path, each left-out reason (disabled, submenu, untitled, `>`, too long, duplicate, already a NoHands phrase, irreversible, reserved phrase, blocked chord, over 200), the id from the bundle ID including the built-in collision and short cases. Every produced draft passes `PackFile.parse` after `PackFile.encode`.
- `MenuShortcutTests` (core): a table of (character, virtual key, mask) to chord or nil.
- `MenuShortcutReaderTests` (mac): a fake tree gives the expected entries (Apple menu skipped, second level not read, shortcut fields read); a missing menu bar throws `noMenuBar`.

None need the microphone, Accessibility or a model. `swift test` and `swift build` pass.

Manual (in the PR): `pack new` with Safari in front; `pack add` the draft; say one of its phrases with Safari in front. Also `pack new --app Finder` and check Empty Trash is listed as `irreversible`.

## Docs

- `docs/app-packs.md` § Write a pack: `pack new` as the first way to start, with the left-out reasons in short.
- `docs/cli.md`: a `pack new [--app <name>] [--out <file>]` row.
- No voice phrase is added, so the voice command table does not change.

## Out of scope

Teaching phrases by voice, a pack editor window, the model writing packs, submenu items, packs with code, sharing or publishing packs (NH-85).

## Calls I made

- **Irreversible items are dropped** even though the validator would accept them with the title as the phrase. A draft is something you install after a skim; Empty Trash or Send should be added on purpose.
- **Phrases NoHands already handles are dropped** (`copy`, `paste`, `new tab`): they add nothing and would fill `pack add`'s "replaces" list.
- **Disabled items are dropped**, as the ticket says, though some are only disabled for lack of a window or selection; the printout says to rerun with content open.
- **Id from the full bundle ID** (`com-apple-safari`), not the app name, so it never takes a short name a built-in or registry pack might use; `-custom` if it still matches a built-in.
- **An installed pack with the same id** is not checked: `pack add` already shows "replaces version X", which is the flow for regenerating a pack.
- **Top-level menu items only**, no submenus: submenus are mostly lists of documents, bookmarks or history that change.
- **`menu_item` titles carry the menu path** (`File > Export…`) so they press that item and not a look-alike elsewhere.
- **A new reader, not a change to `AXMenuReader`**, so reading shortcuts never slows the run-time `menu` command.
- **`--app` reads in the background** without bringing the app forward; no `--app` waits 3 s like `menu --list`.
- **Never overwrites a file**; default name `<id>.json` in the current folder. **Author left empty** rather than filled from the Mac user's name.
- **Commands sorted by phrase** in the file, since that is how `PackFile.encode` writes, rather than menu order.
- **Docs go in `docs/app-packs.md` and `docs/cli.md`**, not `README.md` as the ticket says (README was shortened by NH-119).
