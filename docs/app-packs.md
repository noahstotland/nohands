# App packs

Back to the [README](../README.md).

An app pack adds voice commands for one app, or a few. Its phrases work only while one of its apps is in front, and a pack wins over a built-in phrase there. NoHands ships packs for Terminal, VS Code, Mail, Messages, Safari and Chrome ([Voice commands](voice-commands.md#per-app-commands)); you can install more from a file or from a pack registry.

A pack is data, never code. Installing or loading one cannot run anything, reach the network or act outside its own apps. Each phrase presses a key chord, picks a menu item, opens an app or opens an `https` page, and nothing else.

## Install, list, remove

```bash
swift run nohands-cli pack add my-pack.json
swift run nohands-cli pack list
swift run nohands-cli pack remove notes-extras
```

`pack add` checks the file, then shows what the pack does before it asks `Install? [y/N]`: name, version, author, the apps it works in, every phrase with its actions spelled out on one line (`"new note" -> command-N`, `menu item "Archive Note"`, `open https://host/path`, `open app Foo`), the sites it opens, the apps it opens, any NoHands phrases it replaces inside its apps, and phrases that an earlier pack already holds. It installs only on `y` or `yes`. There is no flag to skip the question. Anything printed from the pack has control, invisible and bidi characters shown as `\u{...}`, so a pack cannot inject terminal escapes. Add the same id again to replace the pack; it keeps its place and its on/off setting.

The menu bar's **Packs** submenu lists each pack with an **On** toggle and **Remove…**. To install from a file, use the CLI; to install from a registry, see the next section. A running NoHands picks up a change from the CLI by itself. Packs live in `~/.config/nohands/packs/<id>/pack.json`.

To see how a pack behaves without speaking, dry-run a phrase with the app in front:

```bash
swift run nohands-cli parse "new folder" --app com.apple.Notes
```

## Get packs from a registry

A registry is one signed list of packs at an `https` address. NoHands looks at it only when you ask: in the menu bar, **Packs > Browse…** opens a window with the list and **Packs > Check for pack updates** looks for newer versions; in the terminal, the `pack search`, `pack install` and `pack update` commands do the same. Nothing is fetched at launch or in the background, and nothing you say can start a fetch.

```bash
swift run nohands-cli pack search notes      # packs whose id, name or description contain "notes"
swift run nohands-cli pack search            # everything the registry lists
swift run nohands-cli pack install notes-extras
swift run nohands-cli pack update            # every installed pack with a newer registry version
swift run nohands-cli pack update notes-extras
```

`search` lists the id, version, name and apps of each match, and notes the ones you already have (`installed`, `update to 1.2.0`). `install` and `update` download the pack, then show the same summary as `pack add` (for an update, also what changed from the version you have) and ask `Install? [y/N]` or `Update? [y/N]`. Only `y` or `yes` goes ahead, and there is no flag to skip the question. In the app, the same summary shows in an alert whose default button is Cancel, so pressing return never installs.

Before you are asked, NoHands has already checked:

- The list is signed by the registry's key, and is not older than the newest list this Mac has seen from that registry.
- The pack's file matches the SHA-256 the list promised, passes every rule in [Limits and rejections](#limits-and-rejections), and has the same id, version and apps as its list entry, so what you see in Browse is what you install.
- A pack is never installed over a newer version. Registry versions are plain numbers such as `1.2.0`; a pack you installed from a file with a version that is not numbers shows `installed from a file` and is never offered an update. Remove it and install it from the registry if you want one.

Nothing is written to `~/.config/nohands/packs/` until all of that has passed and you have said yes. An installed pack then runs from disk, with the network off, like any other.

### Pick a registry

The registry address and its key come from `config.json` ([Configuration](configuration.md)):

```json
{
  "packRegistryURL": "https://packs.example.org/index.json",
  "packRegistryKey": "<the registry's public key, from its publisher>"
}
```

NoHands does not ship with a registry chosen yet. Until one is, **Registry: none set** shows in the Packs menu and nothing is fetched. A registry you set yourself needs its own public key in `packRegistryKey`; without it NoHands shows `Registry has no key, set packRegistryKey in config.json` and fetches nothing. The address must be `https` with a public host name (not `localhost`, an IP address or a local network name). Set `"packRegistryURL": ""` to turn the registry off.

### When it fails

Each message says what happened, and in every case nothing was installed.

| Message | What it means |
|---|---|
| `No pack registry yet, set packRegistryURL in config.json` | No registry is set |
| `The pack registry is off (packRegistryURL is empty)` | You turned it off |
| `Registry has no key, set packRegistryKey in config.json` | The registry has no public key to check it against |
| `Registry URL must be https` | The address is `http` or another scheme |
| `Registry URL needs a public host and no user or password` | The address points at a local or private name, or has a user name in it |
| `No connection, installed packs still work` | The Mac could not reach the host |
| `Timed out, installed packs still work` | A request took over 10 seconds, or the whole fetch over 30 |
| `Registry signature failed, nothing installed` | The list is not signed by your key, or was changed. Check `packRegistryKey` |
| `Registry is older than one already seen, nothing installed` | The host is serving an older list than before (see the serial rule below) |
| `Download didn't match the registry, nothing installed` | The pack file is not the one the list promised |
| `Pack failed checks: ..., nothing installed` | The pack broke one of the rules above, or its id, version or apps differ from its list entry |
| `Registry sent something unusable (...), nothing installed` | The list is malformed, too big, answered with an error, or redirected somewhere not allowed |
| `Couldn't save the registry's version, nothing installed` | NoHands could not write `~/.config/nohands/registry-state.json` |
| `Already installed`, `Older than installed, not installed`, `Installed from a file, can't compare` | The registry has nothing newer to offer for that pack |

Requests follow at most 3 redirects, and each must go to `https` and a public host. A list is limited to 1 MiB and 1,000 packs, and a pack to 64 KiB. What the network sees is in [Privacy](privacy.md).

## Write a pack

The quickest start is to let NoHands read the app's menus. Bring the app forward and run `swift run nohands-cli pack new` (it waits 3 s), or name a running app with `--app Safari`, and add `--out <file>` to pick the file name (the default is `<id>.json` here; an existing file is never overwritten). It writes a draft with one phrase per top-level menu item: the item's title as the phrase, its keyboard shortcut when it has one, otherwise a `menu_item` that presses it. It prints what it left out and why:

- `disabled`: the item was greyed out when read. Open a window with content and run again to catch more.
- `opens a submenu`, `no title`, `title has >`, `no words to say` or `too long to say`: nothing a phrase can press or say.
- `same phrase as ...`: two items with one title; the first stays.
- `already a NoHands phrase`: NoHands already understands it, such as `copy` or `new tab`.
- `irreversible`: Send, Delete and the like (Empty Trash shows as `already a NoHands phrase`). Add one by hand if you want it.
- `rejected: ...`: the pack check refuses it, such as a reserved phrase or a blocked shortcut.
- `over the 200 command limit`.

Edit the draft, then install it with `pack add` like any other file. `pack new` never installs.

`swift run nohands-cli pack builtin terminal` prints the Terminal pack in this format as a starting point (any built-in id works, such as `chrome`). A pack is one JSON file, up to 64 KiB:

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
| `id` | Names the folder: lowercase letters, digits and `-`, 2 to 40 characters, starting with a letter or digit. Not a built-in pack's id: `terminal`, `vs-code`, `mail`, `messages`, `safari` or `chrome` |
| `name`, `version`, `author` | Shown at install and in the menu. Up to 60, 20 and 60 characters; `author` may be empty |
| `bundleIDs` | The apps the pack works in, 1 to 16, letters, digits, `.` and `-`. Find one with `osascript -e 'id of app "Notes"'` |
| `commands` | Each has `phrases` (what you say) and `actions` (what happens, in order) |

Actions:

| `kind` | Keys | Does |
|---|---|---|
| `press_key` | `key`, optional `modifiers` | Presses the chord. Keys: `a` to `z`, `zero` to `nine`, `return`, `tab`, `space`, `delete`, `forwardDelete`, `escape`, `up`, `down`, `left`, `right`, `home`, `end`, `pageUp`, `pageDown`, `f1` to `f12`, `minus`, `equal`, `leftBracket`, `rightBracket`, `semicolon`, `quote`, `comma`, `period`, `slash`, `backslash`, `grave`. Modifiers: `command`, `shift`, `option`, `control`, `function` |
| `menu_item` | `title` | Presses the menu item with that title in the front app, up to 100 characters. Titles match by words at run time and can press a longer title: "Again" can press "Send Again", so name the full title. The install summary shows every title, so you can judge what a pack presses. An empty part around `>` ("Send>", "File > > Save") is rejected. List an app's titles with `nohands-cli menu --list` |
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
- A return-like press after a `menu_item`, or after any chord containing command, in the same command: `return` or `space` with any modifiers (option-return too), control-m or control-j. It could press the button the item or shortcut opened.
- An `open_app` or `open_url` that is not the last action, since focus leaves the pack's app.
- An `open_url` host that is not a plain public name: only ASCII letters, digits, `.` and `-` are allowed (a non-ASCII name is checked as its punycode form), no `%` escapes in the host, no empty label (leading, trailing or double dot), no IP address or number, `localhost`, name without a dot, or name ending `.local`, `.localhost`, `.lan`, `.internal` or `.home.arpa`. This is a check on the name only: a public name can still resolve to a private address, and the pack's author or their DNS controls that.
- A chord that switches apps or reaches the system: any chord with command plus space or tab, command-option-escape (Force Quit), command-option-delete (Delete Immediately, without shift), and the chords that empty the Trash: command with shift and delete or forward delete (command-shift-delete, command-option-shift-delete, and variants with more modifiers). Only those shift chords are allowed, and only when the phrase says "empty" and "trash"; the app-switching chords and command-option-delete are rejected whatever the phrase says.
- A `menu_item` title that is a short form of an irreversible item ("Empty" for "Empty Trash", "Place" for "Place order", "Check" for "Check out") unless the phrase asks for it, for the loose matching above. Only the last non-empty part of a `>` path counts, trimmed, since that is the part matched at run time, so a path such as "Safe > Empty" is held too. A fragment of a name ("Emp", "Plac") is held as well. Run-time menu matching also falls back to matching characters, so a title found inside an irreversible name ("Move" in "Remove", "End" in "Send", "Order", "Out") is rejected unless the phrase allows that verb. A title with an empty part around `>` ("Send>", "Empty Trash >") is rejected.
- A command that closes or quits without saying so. Command-W, command-Q, and menu items such as "Close Window", "Quit Notes" or "Empty Trash" are allowed only when the phrase asks for it: "quit notes" can press command-Q, "zap" cannot.

Other packs and built-ins: where two packs claim the same phrase in the same app, the built-in pack wins, then the pack installed first; the other is listed as not working in the install summary and in `pack list`. A pack may still replace an ordinary NoHands phrase inside its own apps (the summary lists each one), but never a reserved one. A leading `open`, `go to`, `a` or `the` is ignored when a phrase is looked up, as for built-in packs.

## Publish a registry

Anyone can run a registry: two kinds of file on any web host that serves `https`, plus a key to sign with. NoHands does not host one for you.

**1. Make a signing key, once.**

```bash
swift run nohands-cli registry keygen registry.key
```

This writes the private key to `registry.key` (mode 600; it refuses a file that exists or a link) and prints the public key and a key id. Keep the private key off the web server and out of git. The public key is what your users put in `packRegistryKey`.

**2. Write the list.** `index.json` lists your packs. Every key is required and an unknown key rejects the file:

```json
{
  "format": 1,
  "serial": 42,
  "packs": [
    { "id": "notes-extras",
      "name": "Notes extras",
      "author": "Jane Doe",
      "version": "1.2.0",
      "description": "Pin, lock and move notes by voice.",
      "bundleIDs": ["com.apple.Notes"],
      "url": "https://packs.example.org/notes-extras-1.2.0.json",
      "sha256": "<64 lowercase hex characters>" }
  ]
}
```

| Key | Meaning |
|---|---|
| `format` | Always `1` |
| `serial` | A whole number that goes up every time you publish (see the serial rule) |
| `id`, `name`, `author`, `bundleIDs` | The same as in the pack file, and the pack must say the same |
| `version` | 1 to 4 numbers separated by dots (`1`, `1.2`, `1.2.0`), each up to 6 digits. It must equal the pack's `version` |
| `description` | Up to 300 characters, may be empty |
| `url` | Where the pack file is: `https`, public host, no user or password, up to 2048 characters |
| `sha256` | The SHA-256 of the pack file, 64 lowercase hex characters. `shasum -a 256 notes-extras-1.2.0.json` prints it |

Up to 1,000 packs, no repeated `id`, and no built-in pack id (`terminal`, `vs-code`, `mail`, `messages`, `safari`, `chrome`). One bad entry rejects the whole list.

**3. Sign it.**

```bash
swift run nohands-cli registry sign index.json --key registry.key --packs ./packs > registry.json
```

`sign` checks every rule above, then prints the signed file, which you upload to the address in `packRegistryURL`. With `--packs <dir>`, it also reads each pack file from `<dir>` (named like the last part of its `url`, here `notes-extras-1.2.0.json`) and checks its hash and the pack rules, and it refuses to sign if one is wrong. A pack file that is not in the folder is not checked, so keep them all there. `--key` and `--packs` can come in either order. Upload the pack files to the addresses in the list.

The signed file is a small envelope, so the list is signed exactly as written and you never have to worry about how the JSON is laid out:

```json
{
  "format": 1,
  "keyID": "3f9a1c0d7e2b4a56",
  "index": "<the index.json bytes, base64>",
  "signature": "<Ed25519 signature, base64>"
}
```

The signature covers the text `nohands-pack-index-v1`, a newline, and then the index bytes. `keyID` only picks a key; trust comes from the key a user has set.

**The serial rule.** NoHands remembers the highest `serial` it has accepted from each registry address, in `~/.config/nohands/registry-state.json`, and refuses a lower one. This stops someone replaying an old list to hide a newer pack. So raise `serial` every time you publish, and never serve a list with a lower number than one you have served: users would see `Registry is older than one already seen`, and the only fix on their side is to delete that file. Serving the same serial again is fine.

**Rotating the key.** NoHands trusts only the one key in `packRegistryKey`. To change keys, make a new one with `registry keygen`, sign with it, and tell your users the new public key to put in `packRegistryKey`. Until they do, they see `Registry signature failed`.

**If a key is stolen, there is no way to cancel it remotely.** NoHands never asks anyone whether a key is still good. A user stops trusting a key only when they change `packRegistryKey` (or, for a registry that ships inside NoHands, install a release without it). So protect the private key, and if it leaks, tell your users to change their key. The damage is limited: a signer can only offer pack data that passes the rules in this page (key chords, menu items and `https` pages), every install and update still shows the user every phrase and waits for their yes, and an older version is never installed over a newer one.

Design and reasoning: `docs/superpowers/specs/2026-11-15-nh-80-installable-packs-design.md`, and for the registry `docs/superpowers/specs/2026-11-16-nh-85-pack-marketplace-design.md`.
