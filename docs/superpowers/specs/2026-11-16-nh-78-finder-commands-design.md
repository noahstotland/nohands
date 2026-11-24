# NH-78: Finder voice commands: Design

**Date:** 2026-11-16  **Ticket:** [NH-78](https://github.com/noahstotland/nohands/issues/78)
**Status:** Shipped
**Shipped:** in PR #169, with differences: [as-built](../as-built/2026-11-16-nh-78-finder-commands.md)

## Intent

Finder is where files are found, moved and cleaned up, and today almost none of its own commands can be said. The
generic `copy`, `paste`, `select all`, `new tab`, `go back` and `undo` work, but "new folder", "list view", "get info"
and "go to downloads" do not. Worse, "go to downloads" in Finder today runs the global address-bar rule (⌘L, type,
return), and ⌘L in Finder is not an address bar. This ticket adds a Finder pack (`com.apple.finder`) on the NH-76
mechanism, the same shape as the Mail and Terminal packs: one Core table file, one entry in `AppPacks.all`, a table
test and rows in `docs/voice-commands.md`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance: new window, new folder, close window, go to home, desktop, documents,
downloads, applications and iCloud Drive, go up a folder, the four view modes, the sidebar and path bar, get info,
open, Quick Look, duplicate, make alias, rename, move here (paste as a move), move to Trash, show hidden files and
search. `new tab`, `go back`, `go forward`, `copy`, `paste` and `select all` from the ticket's list already work
through the global table and are not repeated.

Non-goals (the ticket's Out of scope): opening a file or folder by its name (NH-58), emptying the Trash (NH-52), a
spoken confirm for fixed phrases (NH-149), sort and group by, tags, the status bar and preview pane, Go menu places
beyond the six named ones, and other file managers.

Anti-goals, which would make this a failure even if it works:

- A Finder phrase changes what a phrase does in any other app, or with no app in front.
- Any NH-58 phrase (`open the downloads folder`, `open trash`, `open file budget`, `open my last keynote`) or the
  NH-52 `empty trash` does something different with Finder in front than with no app in front.
- A short common word (`delete`, `trash`, `home`, `up`, `open home`) starts trashing or navigating.
- Any phrase empties the Trash or deletes immediately, with or without a prompt.
- A stop phrase reaches the pack, or a pack phrase is "stop".

## What the code forces

- **The lookup order** (`CommandGrammar.parse`): the pack's whole phrase, then the global table, then the pack again
  with one leading `open` or `go to` and one article dropped (`PhraseLead.strip`), then the patterns, `open` among
  them (NH-58's `parseOpenFile`, then sites, then apps). So a pack key `downloads` would also catch `open downloads`
  and `open the downloads`, and a key `downloads folder` would catch NH-58's `open the downloads folder` before
  `parseOpenFile` sees it. To keep NH-58 untouched in Finder, every navigation key is a whole phrase that starts
  with `go to` (`go to downloads`, `go to the downloads folder`), never a bare folder name. The whole-phrase lookup
  hits it first, and its lead-stripped form (`downloads`) is not a key, so `open downloads` still goes where it goes
  today.
- **A pack phrase wins over the global one** with the same words. The pack takes exactly one global phrase,
  `close window` (see Calls), and leaves `home`, `delete`, `up`, `down`, `find`, `undo`, `copy`, `paste`,
  `select all`, `show desktop` and `empty trash` alone.
- **Built-in packs must survive the validator round trip** (`builtInPacksRoundTripThroughTheFormat`, NH-80). Every
  entry here is one chord or one menu item: no command-space or command-tab, no ⌥⌘⌫ (Delete Immediately), no ⇧⌘⌫
  (Empty Trash), no return or space after a command chord, and no menu title carrying a guarded verb (`Make Alias`,
  `Put Back` and `Close Window` hold none; `close window` names its close word, so `ShortcutGuard` allows it).
- **The grammar runs a fixed phrase without a confirm.** NH-61's `IrreversibleGuard` and its "say yes" pause cover
  only steps the model chose in a task; NH-149 (open) would add a confirm for marked fixed phrases. This pack needs
  none, because nothing in it is irreversible (see Confirms and undo).
- **Finder's titles on macOS 14.5**, read from `Finder.app/Contents/Resources/en.lproj/Localizable.strings` on this
  machine: New Folder, Get Info, Duplicate, Make Alias, Move to Trash, Put Back, Rename, Go to Folder…, Show/Hide
  Sidebar, Show/Hide Path Bar. Close Window lives in a nib and is checked by hand.

## How each phrase differs from NH-58 and NH-52

| Say | Who | What happens |
|---|---|---|
| `open the downloads folder`, `open my documents folder`, `open trash` | NH-58, anywhere | Opens the folder in Finder through NSWorkspace (a new window, or a tab if Finder prefers tabs). Unchanged in Finder |
| `open file budget`, `open the reports folder`, `open my last keynote` | NH-58, anywhere | Finds and opens by name. Unchanged in Finder |
| `go to downloads`, `go to the downloads folder`, `go to my documents` | Finder pack, Finder in front | Changes the front Finder window to that folder (the Go menu chord). Outside Finder unchanged (address bar or site rule) |
| `open`, `open it`, `open this` | Finder pack | Opens the selected items (⌘O). A bare `open` goes to the model today |
| `empty trash` | NH-52, anywhere | Finder's own Empty Trash with its own prompt. Unchanged in Finder; the pack has no empty phrase |
| `show desktop` | global system command | Still reveals the desktop (pushes windows aside). `go to desktop` is the Finder window going to the Desktop folder |
| `move to trash`, `trash this` | Finder pack | Moves the selection to the Trash (⌘⌫); `undo` or `put back` brings it back |

## Confirms and undo

No phrase in this pack waits for a spoken "say yes", and none needs NH-149:

- **Move to Trash** (⌘⌫) is not irreversible. `undo` (global ⌘Z) puts the items back in Finder, and `put back` does
  the same from inside the Trash. On a volume with no Trash (some network or external disks), Finder itself asks
  "will be deleted immediately"; NoHands does not answer it (say `enter` or `escape`). The trash phrases all say
  `trash`, `move` or `delete file`; a bare `delete` stays backspace and a bare `trash` is not a phrase (`go to trash`
  must never trash the selection).
- **Rename** only presses Return, which starts editing the name. Nothing changes until `enter`; `escape` cancels,
  and `undo` reverts a finished rename.
- **Move here** (⌥⌘V) moves files; `undo` moves them back. A name clash shows Finder's own replace prompt.
- **Put back** is the menu item `File > Put Back`, which exists only in the Trash, so outside the Trash it fails with
  "no menu item" instead of pressing ⌘⌫ (which would trash the selection).
- **Empty Trash** stays NH-52's, behind Finder's own confirm. **Delete Immediately** (⌥⌘⌫) is not added, and the
  validator rejects it in any pack.

If NH-149 later wants to mark Finder phrases, none qualifies under its "irreversible" rule; that ticket decides.

## Approaches

1. **One pack of chords in its own Core file, `go to` keys spelled out (chosen).** Testable as a table, no menu walk,
   NH-58 phrases untouched.
2. **Bare folder keys (`downloads`, `desktop`) and let the lead drop do the rest.** Half the keys, but `open
   downloads` and `open the downloads folder` would change meaning in Finder, and `home` would shadow the Home key.
3. **Menu items by title throughout.** Steadier against remapped chords, but the show/hide titles flip, every phrase
   pays the Accessibility walk, and "new folder" would match "New Folder with Selection". Kept as the fallback for a
   chord the manual check finds broken; `close window`, `make alias` and `put back` use titles already (see Calls).

## How it works

### `NoHandsCore/FinderPack.swift`

```swift
extension AppPack {
    static let finder: AppPack = { ... AppPack(name: "Finder", bundleIDs: ["com.apple.finder"], phrases: phrases) }()
}
```

and `.finder` appended to `AppPacks.all`. Nothing else in Core, Mac or the pipeline changes. Phrases (normalized keys):

| Phrases | Action |
|---|---|
| `new window`, `new finder window` | ⌘N |
| `new folder`, `make a new folder`, `make new folder`, `create a folder`, `create folder`, `create a new folder` | ⇧⌘N |
| `close window`, `close the window`, `close finder window` | `.menuItem("File > Close Window")` |
| `go to <place>` for each place below, as `go to X`, `go to the X`, `go to my X`, `go to X folder`, `go to the X folder`, `go to my X folder` | the place's chord |
| place `home` (also `go home`) | ⇧⌘H |
| place `desktop` | ⇧⌘D |
| place `documents` | ⇧⌘O |
| place `downloads` | ⌥⌘L |
| place `applications`, `apps` | ⇧⌘A |
| place `icloud drive`, `icloud` | ⇧⌘I |
| `go to folder`, `go to a folder` | ⇧⌘G (Go to Folder…; then `type ~/Projects`, `enter`) |
| `go up`, `go up a folder`, `go up one folder`, `up a folder`, `up one folder`, `go to the parent folder`, `go to parent folder`, `go to the enclosing folder`, `go to enclosing folder` | ⌘↑ |
| `icon view`, `view as icons`, `as icons` | ⌘1 |
| `list view`, `view as list`, `as list` | ⌘2 |
| `column view`, `view as columns`, `as columns` | ⌘3 |
| `gallery view`, `view as gallery`, `as gallery` | ⌘4 |
| `show sidebar`, `hide sidebar`, `toggle sidebar` | ⌃⌘S (toggles) |
| `show path bar`, `hide path bar`, `toggle path bar` | ⌥⌘P (toggles) |
| `get info`, `show info`, `info` | ⌘I |
| `open`, `open it`, `open this`, `open selection`, `open selected`, `open the selection` | ⌘O |
| `quick look`, `quick look this`, `preview this`, `close quick look` | space (toggles the Quick Look panel) |
| `duplicate`, `duplicate this`, `duplicate it`, `duplicate file` | ⌘D |
| `make alias`, `make an alias`, `create alias`, `create an alias` | `.menuItem("File > Make Alias")` |
| `rename`, `rename this`, `rename it`, `rename file`, `rename this file` | return (starts editing the name) |
| `move here`, `move it here`, `move items here`, `move them here`, `paste as move`, `paste here as a move` | ⌥⌘V |
| `move to trash`, `move to the trash`, `move it to the trash`, `move it to trash`, `move this to the trash`, `trash this`, `trash it`, `trash file`, `trash this file`, `delete file`, `delete this file` | ⌘⌫ |
| `put back`, `put it back` | `.menuItem("File > Put Back")` |
| `show hidden files`, `hide hidden files`, `toggle hidden files` | ⇧⌘. (toggles) |
| `search`, `search finder`, `search files` | ⌘F |

The `go to` keys are built in a loop over the places and the six forms, so the table stays readable.

### `docs/voice-commands.md`

Rows in the Per-app commands table (App `Finder`), one per group above, and a paragraph: the global `new tab`,
`close tab`, `go back`, `go forward`, `copy`, `paste`, `select all`, `undo` and `find` work in Finder as elsewhere;
`go to <place>` changes the front window while `open the <place> folder` opens it as before; the sidebar, path bar,
hidden files and Quick Look toggle; `move to trash` is undone by `undo` or `put back`, and `empty trash` asks
Finder's own question. The ticket says README; the table moved to `docs/voice-commands.md` in NH-119. Only Finder
rows are added; NH-74 (Chrome) and NH-77 (Safari) add their own rows next to them.

## Tests

Core, table-driven (`FinderPackTests.swift`, no permissions), through the shipped `CommandGrammar()` so the
`AppPacks.all` line is tested too:

- **Finder in front:** a sample phrase from each group, including a lead or article form (`go to the downloads
  folder`, `go to my documents`, `open a new folder`), resolves to its action. With `com.apple.Safari` or no app in
  front, each sample does not resolve to its Finder action.
- **Nothing else changes in Finder:** these give with Finder in front exactly what they give with no app in front:
  `open the downloads folder`, `open my documents folder`, `open trash`, `open file budget`, `open the reports
  folder`, `open my last keynote`, `open downloads`, `open home`, `empty trash`, `show desktop`, `home`, `delete`,
  `up`, `copy`, `paste`, `select all`, `undo`, `find`, `go back`, `new tab`, `stop`, `cancel`. And `trash` and
  `go to trash` never resolve to ⌘⌫.

The NH-80 round trip test covers the new pack once it is in `AppPacks.all`.

Manual on macOS 14 (listed in the PR, with any phrase that fails): each group by `nohands-cli parse "<phrase>" --app
com.apple.finder` for the dry run and by voice in Finder; `move to trash` then `undo`; `put back` in and outside the
Trash; `close window` with one tab and with two; `rename`, `type new name`, `enter`; `go to icloud drive` with and
without iCloud signed in.

## Calls I made

- **No phrase asks for a spoken yes, and none is marked for NH-149.** Move to Trash is undone by `undo` or `put
  back`, rename only starts editing, and the two irreversible Finder actions (Empty Trash, Delete Immediately) are not
  in the pack. A volume without a Trash gets Finder's own "deleted immediately" prompt, which NoHands does not answer.
- **`delete file` and `delete this file` trash the selection**, as Finder's own menu does for ⌘⌫; a bare `delete`
  stays backspace and a bare `trash` is not a phrase, so `go to trash` cannot trash anything.
- **Navigation is `go to <place>` only, never a bare place name or `open <place>`.** That keeps every NH-58 phrase
  doing what it does now, also in Finder: `open the downloads folder` opens a window, `go to downloads` moves the
  front window. `open downloads` (no "folder") stays the app rule, as today.
- **`close window` is overridden in Finder and uses the menu title.** The global phrase sends ⇧⌘W, which closes the
  window only when it has tabs; Finder's `Close Window` item works either way.
- **`put back` is the menu item, not ⌘⌫**, so outside the Trash it fails safely instead of trashing the selection.
- **`make alias` is the menu item**, because its chord moved between macOS versions (⌘L, now ⌃⌘A).
- **Sidebar, path bar, hidden files and Quick Look are toggle chords.** `show sidebar` on a shown sidebar hides it, as
  in VS Code; the menu titles flip, so a title match would fail half the time.
- **`open` alone opens the selection** (⌘O). Today a bare `open` goes to the model.
- **`info` alone is a phrase** (Get Info), as in Messages.
- **The six places are the ticket's**; Recents, AirDrop, Utilities, Network and Computer are left out, as are the
  status bar and preview pane. Easy to add later as rows.
- **`search` focuses Finder's search** (⌘F); the global `search for <words>` keeps its current behaviour.
- **Synonyms the ticket did not list** (`create folder`, `trash this`, `view as list`, `preview this`, `move here`).
- **`docs/app-packs.md` is not changed**: its reserved-id lines name only `terminal` and are already stale for Mail,
  VS Code and Messages; NH-74 and NH-77 edit the same area, so the documenter decides in one place.
- **Chords come from Finder's menus as documented by Apple**; the strings file confirmed the titles but not the key
  equivalents. A chord that fails the manual check becomes `.menuItem(<title>)` and the PR says which.

## Follow-ups (not in this ticket)

- `go to recents`, `go to airdrop`, `show status bar`, `show preview`, sort by name, date and size.
- "search finder for <words>" in one phrase.
