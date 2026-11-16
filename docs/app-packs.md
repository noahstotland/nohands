# App packs

Back to the [README](../README.md).

An app pack adds voice commands for one app, or a few. Its phrases work only while one of its apps is in front, and a pack wins over a built-in phrase there. NoHands ships a Terminal pack ([Voice commands](voice-commands.md#per-app-commands)); you can install more from a file.

A pack is data, never code. Installing or loading one cannot run anything, reach the network or act outside its own apps. Each phrase presses a key chord, picks a menu item, opens an app or opens an `https` page, and nothing else.

## Install, list, remove

```bash
swift run nohands-cli pack add my-pack.json
swift run nohands-cli pack list
swift run nohands-cli pack remove notes-extras
```

`pack add` checks the file, then shows what the pack does before it asks `Install? [y/N]`: name, version, author, the apps it works in, every phrase with its actions spelled out on one line (`"new note" -> command-N`, `menu item "Archive Note"`, `open https://host/path`, `open app Foo`), the sites it opens, the apps it opens, any NoHands phrases it replaces inside its apps, and phrases that an earlier pack already holds. It installs only on `y` or `yes`. There is no flag to skip the question. Anything printed from the pack has control, invisible and bidi characters shown as `\u{...}`, so a pack cannot inject terminal escapes. Add the same id again to replace the pack; it keeps its place and its on/off setting.

The menu bar's **Packs** submenu lists each pack with an **On** toggle and **Remove…**; it does not install. A running NoHands picks up a change from the CLI by itself. Packs live in `~/.config/nohands/packs/<id>/pack.json`.

To see how a pack behaves without speaking, dry-run a phrase with the app in front:

```bash
swift run nohands-cli parse "new folder" --app com.apple.Notes
```

## Write a pack

`swift run nohands-cli pack builtin terminal` prints the Terminal pack in this format as a starting point. A pack is one JSON file, up to 64 KiB:

```json
{
  "format": 1,
  "id": "notes-extras",
  "name": "Notes extras",
  "version": "1.0.0",
  "author": "Jane Doe",
  "bundleIDs": ["com.apple.Notes"],
  "commands": [
    { "phrases": ["new note", "make a note"],
      "actions": [{ "kind": "press_key", "key": "n", "modifiers": ["command"] }] },
    { "phrases": ["new folder"],
      "actions": [{ "kind": "press_key", "key": "n", "modifiers": ["command", "shift"] }] },
    { "phrases": ["pin note"],
      "actions": [{ "kind": "menu_item", "title": "Pin Note" }] },
    { "phrases": ["notes help"],
      "actions": [{ "kind": "open_url", "url": "https://support.apple.com/guide/notes/welcome/mac" }] }
  ]
}
```

Every key is required unless marked optional, and an unknown key anywhere rejects the file.

| Key | Meaning |
|---|---|
| `format` | Always `1` |
| `id` | Names the folder: lowercase letters, digits and `-`, 2 to 40 characters, starting with a letter or digit. Not `terminal` (a built-in pack) |
| `name`, `version`, `author` | Shown at install and in the menu. Up to 60, 20 and 60 characters; `author` may be empty |
| `bundleIDs` | The apps the pack works in, 1 to 16, letters, digits, `.` and `-`. Find one with `osascript -e 'id of app "Notes"'` |
| `commands` | Each has `phrases` (what you say) and `actions` (what happens, in order) |

Actions:

| `kind` | Keys | Does |
|---|---|---|
| `press_key` | `key`, optional `modifiers` | Presses the chord. Keys: `a` to `z`, `zero` to `nine`, `return`, `tab`, `space`, `delete`, `forwardDelete`, `escape`, `up`, `down`, `left`, `right`, `home`, `end`, `pageUp`, `pageDown`, `f1` to `f12`, `minus`, `equal`, `leftBracket`, `rightBracket`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backslash`, `grave`. Modifiers: `command`, `shift`, `option`, `control`, `function` |
| `menu_item` | `title` | Presses the menu item with that title in the front app, up to 100 characters. Titles match by words at run time: "Archive" can press "Archive Note", so name the full title. List an app's titles with `nohands-cli menu --list` |
| `open_app` | `app` | Opens or focuses the app by name, up to 60 characters. Must be the last action in its command |
| `open_url` | `url` | Opens the page in your default browser. `https` only, with a public host name (see below), no user or password, up to 2048 characters. Must be the last action in its command |

Anything else is rejected: typing text, clicks, mode changes, running commands.

### Limits and rejections

A pack with any problem is rejected whole, and the error names the first rule broken. The rules:

- The file is over 64 KiB, is not JSON, has a missing or unknown key, or its `format` is not 1.
- More than 200 commands, 500 phrases in all, or 8 actions in one command; a command with no phrases or no actions.
- A phrase over 60 characters or 8 words, empty once punctuation is stripped, or repeated (after lowercasing and dropping `. , ! ?`).
- A control character in any text.
- A **reserved phrase**: "stop" and the other stop phrases, and every phrase that changes mode or lets go of the mouse ("go to sleep", "wake up", "dictation mode", "stop dictating", "release click", "hide numbers", "cancel" and similar). Those belong to NoHands.
- A command with more than 2 key presses that have no command or option, because single keys add up to typed text. Control-letter chords count toward the 2; only command and option chords are exempt.
- A return-like press after a `menu_item`, or after any chord containing command, in the same command: `return`, `space` (alone or with shift), control-return, control-m or control-j. It could press the button the item or shortcut opened.
- An `open_app` or `open_url` that is not the last action, since focus leaves the pack's app.
- An `open_url` host that is not a plain public name: only ASCII letters, digits, `.` and `-` are allowed (a non-ASCII name is checked as its punycode form), no `%` escapes in the host, no empty label (leading, trailing or double dot), no IP address or number, `localhost`, name without a dot, or name ending `.local`, `.localhost`, `.lan`, `.internal` or `.home.arpa`. This is a check on the name only: a public name can still resolve to a private address, and the pack's author or their DNS controls that.
- A chord that switches apps or reaches the system: any chord with command plus space or tab, command-option-escape (Force Quit), and the chords that empty the Trash or delete at once: command with delete or forward delete plus shift or option (command-shift-delete, command-option-delete, and variants with more modifiers). Only the delete chords are allowed, and only when the phrase says "empty" and "trash"; the app-switching chords are rejected whatever the phrase says.
- A `menu_item` title that is a short form of an irreversible item ("Empty" for "Empty Trash", "Place" for "Place order", "Check" for "Check out") unless the phrase asks for it, for the loose matching above. Only the part after the last `>` counts, since that is the part matched at run time, so a path such as "Safe > Empty" is held too. A fragment of a name ("Emp", "Plac") is held as well.
- A command that closes or quits without saying so. Command-W, command-Q, and menu items such as "Close Window", "Quit Notes" or "Empty Trash" are allowed only when the phrase asks for it: "quit notes" can press command-Q, "zap" cannot.

Other packs and built-ins: where two packs claim the same phrase in the same app, the built-in pack wins, then the pack installed first; the other is listed as not working in the install summary and in `pack list`. A pack may still replace an ordinary NoHands phrase inside its own apps (the summary lists each one), but never a reserved one. A leading `open`, `go to`, `a` or `the` is ignored when a phrase is looked up, as for built-in packs.

Design and reasoning: `docs/superpowers/specs/2026-11-15-nh-80-installable-packs-design.md`.
