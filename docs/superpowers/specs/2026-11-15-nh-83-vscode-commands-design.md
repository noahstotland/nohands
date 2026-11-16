# NH-83: VS Code voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-83](https://github.com/noahstotland/nohands/issues/83)
**Status:** Shipped
**Shipped:** in PR #144, as specified

## Intent

VS Code is driven almost entirely by chords and the command palette, so a keyboard-free user can't move around it
or edit with it. This ticket adds the second app pack on the NH-76 mechanism: VS Code (`com.microsoft.VSCode`), with
phrases for the command palette, quick open, go to line and definition, editors, side bar views, the common edit
commands, the integrated terminal, debugging and the window. It is a table file, a line in the pack registry, a test
and rows in `docs/voice-commands.md`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals (the ticket's Out of scope): word, line or phrase editing beyond these commands (NH-54 already covers it in
any text field), rewriting code with the model, running commands in the integrated terminal, users who rebind VS
Code's keys, and forks (Cursor, Windsurf, VSCodium).

Anti-goals, which would make this a failure even if it works:

- A VS Code phrase changes what a phrase does in any other app, or with no app in front.
- Any phrase is "stop" or contains "stop", or a stop phrase reaches the pack. That is why there is no
  "stop debugging" phrase (see Calls).
- A global phrase that already does the right thing in VS Code starts doing something else there.
- A phrase types text into the editor or the palette on its own.

## What the code forces

- **The pack mechanism exists** (`NoHandsCore/AppPack.swift`, NH-76; first used by Terminal, NH-84).
  `AppPacks.all = [.terminal]`; a pack is a `[String: [Action]]` of normalized phrases to chords or `.menuItem(title)`.
  `CommandGrammar.parse(_:frontmost:)` checks the pack on the whole phrase before the global table, then on the phrase
  without a leading "open" / "go to" and article, before `menu <words>`, tabs, text edits, media and the patterns.
  So a pack phrase wins over `find <words>` ("find references"), the `go to …` caret moves and `open <app>`
  ("open settings"). A stop phrase never reaches a pack. `shippedPacksAreWellFormed` (`AppPackTests.swift`) already
  checks every shipped pack for stop phrases, empty actions and unnormalized keys.
- **An entry can hold several actions**, run in order, so a two-step chord (VS Code's ⌘K Z) is two `.pressKey`s.
- **`.menuItem(title)` searches submenus** (`MenuMatch`, NH-76), and VS Code on macOS uses the native menu bar, so
  a menu fallback reaches View › Appearance and Run items.
- **Keys are posted at the HID event tap** (`InputSynthesizer`), where macOS system shortcuts still fire. Plain F11
  is Show Desktop by default on macOS 14, so a synthesized F11 may never reach VS Code.
- **Three global phrases do the wrong thing in VS Code**: `new tab` (⌘T is Go to Symbol in Workspace), `go back` /
  `go forward` (⌘[ and ⌘] are Outdent and Indent Line: they edit the code), and `next tab` / `previous tab` (⌃Tab
  opens VS Code's recently used editor picker, so it toggles between the last two editors instead of moving along).
  The pack overrides these. The rest match VS Code: `save` ⌘S, `find` ⌘F, `close tab` ⌘W, `close window` ⇧⌘W,
  `full screen` ⌃⌘F, `undo`, `redo`, `copy`, `cut`, `paste`, `select all`, `minimize`, `quit app`, `hide app`.
- **VS Code 1.109.3's default macOS keybindings**, read from the installed app's
  `out/vs/workbench/workbench.desktop.main.js` on this machine (keybinding registrations, decoded):

  | Command | Shortcut |
  |---|---|
  | Show All Commands / Quick Open / Go to Line | ⇧⌘P / ⌘P / ⌃G |
  | Go to Definition / Go to References | F12 / ⇧F12 |
  | Open Next / Previous Editor | ⌥⌘→ / ⌥⌘← |
  | Close Editor / Split Editor / New Untitled File | ⌘W / ⌘\ / ⌘N |
  | Toggle Primary Side Bar | ⌘B |
  | Explorer / Source Control / Extensions / Problems / Search | ⇧⌘E / ⌃⇧G / ⇧⌘X / ⇧⌘M / ⇧⌘F |
  | Save All / Format Document / Rename Symbol / Toggle Line Comment | ⌥⌘S / ⇧⌥F / F2 / ⌘/ |
  | Move Line Up / Down / Copy Line Down | ⌥↑ / ⌥↓ / ⇧⌥↓ |
  | Replace / Replace in Files | ⌥⌘F / ⇧⌘H |
  | Toggle Terminal / New Terminal | ⌃\` / ⌃⇧\` |
  | Start Debugging and Continue / Toggle Breakpoint | F5 / F9 |
  | Step Over / Step Into / Step Out | F10 / F11 / ⇧F11 |
  | Zen Mode / Toggle Full Screen / New Window / Settings | ⌘K Z / ⌃⌘F / ⇧⌘N / ⌘, |
  | Go Back / Go Forward | ⌃- / ⌃⇧- |

  `Key` already has every key these need (`f2`, `f5`, `f9`…`f12`, `backslash`, `grave`, `slash`, `minus`, `comma`).

## Approaches

1. **One pack of chords in its own Core file, menu items only where a chord can't get through (chosen).** Fast, a
   plain table to test, and each chord is a default VS Code shows in its menus.
2. **Menu items by title for everything.** Survives rebinding (out of scope), but every phrase pays the Accessibility
   menu walk and some commands (quick open, go to references, sidebar views) have no menu item or a long submenu path.
3. **Command palette plus typed command names** (⇧⌘P, type "Format Document", return). Reaches anything, but types
   into VS Code, is slow, and depends on the palette's fuzzy ranking. Not used.

## How it works

### `NoHandsCore/VSCodePack.swift`

```swift
extension AppPack {
    static let vscode = AppPack(name: "VS Code", bundleIDs: ["com.microsoft.VSCode"], phrases: [ ... ])
}
```

and `AppPacks.all = [.terminal, .vscode]`. Phrases (normalized keys; the lead stripping means "open the explorer"
and "go to the problems" reach `explorer` and `problems`):

| Phrases | Action |
|---|---|
| `command palette`, `show commands`, `show all commands` | ⇧⌘P |
| `quick open`, `go to file`, `find file` | ⌘P |
| `go to line` | ⌃G |
| `go to definition`, `definition` | F12 |
| `find references`, `find all references`, `go to references`, `references` | ⇧F12 |
| `next editor`, `next tab` | ⌥⌘→ |
| `previous editor`, `previous tab` | ⌥⌘← |
| `close editor`, `close file` | ⌘W |
| `split editor`, `split the editor` | ⌘\ |
| `toggle sidebar`, `show sidebar`, `hide sidebar`, `sidebar` (and each with `side bar`) | ⌘B |
| `explorer`, `show explorer`, `file explorer` | ⇧⌘E |
| `source control`, `show source control` | ⌃⇧G |
| `extensions`, `show extensions` | ⇧⌘X |
| `problems`, `show problems` | ⇧⌘M |
| `save all` | ⌥⌘S |
| `format document`, `format file`, `format` | ⇧⌥F |
| `rename symbol`, `rename` | F2 |
| `toggle comment`, `comment line`, `comment`, `uncomment` | ⌘/ |
| `move line up`, `move line down` | ⌥↑, ⌥↓ |
| `duplicate line`, `copy line down` | ⇧⌥↓ |
| `find in files`, `search in files`, `search files` | ⇧⌘F |
| `replace`, `find and replace` | ⌥⌘F |
| `replace in files` | ⇧⌘H |
| `toggle terminal`, `show terminal`, `hide terminal` | ⌃\` |
| `new terminal` | ⌃⇧\` |
| `start debugging`, `debug`, `continue`, `continue debugging` | F5 |
| `toggle breakpoint`, `breakpoint`, `add breakpoint`, `remove breakpoint` | F9 |
| `step over` | F10 |
| `step into`, `step in` | `.menuItem("Step Into")` |
| `step out` | ⇧F11 |
| `zen mode`, `toggle zen mode`, `exit zen mode`, `leave zen mode` | ⌘K, then Z |
| `new window` | ⇧⌘N |
| `settings`, `preferences` | ⌘, |
| `new tab`, `new file` | ⌘N |
| `go back`, `go forward` | ⌃-, ⌃⇧- |

After `command palette`, `quick open` or `go to line` the user says the rest with the existing commands: `type format
document`, `type 42`, `enter` (or dictation mode).

### `docs/voice-commands.md`

Rows in the Per-app commands table (App `VS Code`): one row per group above, grouped as Navigate, Edit, Terminal
and debug, Window, plus a sentence noting that the global `save`, `find`, `close tab`, `close window`, `full
screen`, `undo`, `redo`, `copy`, `paste` and `select all` work in VS Code as they do elsewhere, that `new tab`,
`next tab`, `previous tab`, `go back` and `go forward` do the VS Code thing there, that `open settings` opens VS
Code's settings while VS Code is in front (`open system settings` still opens System Settings), and that there is no
spoken "stop debugging" (`stop` always halts NoHands; use the debug toolbar or `menu stop debugging`).

## Tests

Core, table-driven (`VSCodePackTests.swift`, Core only, no permissions), the shape of `TerminalPackTests`:

- **VS Code in front:** a sample phrase from every row above (including the lead forms "open the explorer", "open
  settings", "go to the problems" and the overrides `new tab`, `next tab`, `previous tab`, `go back`, `go forward`),
  plus the matching globals (`save`, `find`, `close tab`, `close window`, `full screen`), resolves to its action with
  the shipped `CommandGrammar()`, so the registry line is tested too.
- **Another app or none in front:** each sampled pack phrase does not resolve to its VS Code action with
  `com.apple.Safari`, `com.apple.Terminal` or no app in front.
- **No stop:** no VS Code phrase is a stop phrase or has "stop" as a word; "stop", "cancel" and "cancel that" with VS
  Code in front give what they give with no app in front.
- **Text edits still parse:** `replace foo with bar` with VS Code in front and a text field focused still gives the
  NH-54 replace edit, not ⌥⌘F.

Manual on macOS 14 with VS Code 1.109 and default keybindings (listed in the PR, with any phrase that fails and what
it fell back to): each phrase through `nohands-cli parse --app com.microsoft.VSCode "<phrase>"` for the dry run and
by voice in the app; F5, F9, F10 and ⇧F11 reach VS Code during a debug session; ⌘K Z toggles zen mode; ⌃\` toggles
the terminal on a US layout.

## Calls I made

- **The pack overrides five global phrases in VS Code.** `new tab` becomes New Untitled File (⌘N) instead of ⌘T (Go
  to Symbol), `next tab` / `previous tab` become Open Next / Previous Editor (⌥⌘→ / ⌥⌘←) instead of ⌃Tab (the recent
  editors picker), and `go back` / `go forward` become VS Code's Go Back / Go Forward (⌃- / ⌃⇧-) instead of ⌘[ / ⌘],
  which outdent and indent the current line.
- **`open settings` opens VS Code's settings while VS Code is in front** (the pack has `settings`, and the lead
  "open" is dropped before the pack lookup). `open system settings` still opens System Settings.
- **No bare `terminal` phrase**, so `open terminal` still opens the Terminal app from VS Code; the integrated
  terminal is `toggle terminal` / `show terminal` / `new terminal`.
- **No "stop debugging" phrase.** The ticket doesn't list it, and any phrase with "stop" in it is ruled out; `menu stop
  debugging` should reach the menu item through the generic menu command (checked by hand, not added here). A non-stop synonym (`end debugging`) is left for a follow-up.
- **Step into is the Run menu's `Step Into` item, not F11**, because plain F11 is macOS's Show Desktop by default and
  the synthesized key goes through system shortcuts. Every other phrase is a chord. A chord that fails the manual check
  switches to `.menuItem(<title>)` (Save All, Format Document, Toggle Line Comment, Step Out, Zen Mode…) and the PR
  says which.
- **Show, hide and toggle sidebar are all ⌘B**, and so are show and hide terminal (⌃\`): VS Code has only a toggle
  shortcut, and NoHands doesn't read whether the side bar is open, so `hide sidebar` on a hidden side bar shows it.
  Same for `exit zen mode` (a toggle).
- **Zen mode is the two-step chord ⌘K then Z**, sent as two key presses in one entry. Fallback: `.menuItem("Zen
  Mode")` under View › Appearance.
- **`find references` is Go to References (⇧F12, the inline peek)**, not Find All References (⌥⇧F12, the side
  panel).
- **`duplicate line` is Copy Line Down (⇧⌥↓)**; VS Code has no command named "duplicate line" with a default key.
- **`continue` and `start debugging` are both F5**, which is how VS Code binds them (start when idle, continue when
  paused). `resume` stays the global media play key.
- **No "go to line 42" or "command palette format document" in one phrase.** Packs hold exact phrases only; the user
  opens the box and then says `type 42` / `enter`. A pack pattern is a follow-up.
- **Only `com.microsoft.VSCode`.** VS Code Insiders (`com.microsoft.VSCodeInsiders`) has the same keys but can't be
  checked here, and forks are out of scope.
- **Added synonyms the ticket did not list** (`show commands`, `find file`, `definition`, `references`, `close
  file`, `format`, `rename`, `comment`, `uncomment`, `search files`, `find and replace`, `replace in files`,
  `debug`, `breakpoint`, `step in`, `preferences`, `new file`), and the bare view names so `open the explorer` works.
- **The pack lives in its own file** (`VSCodePack.swift`) like Terminal's, so the sibling app packs (NH-79, NH-81,
  NH-82) only touch the one registry line.

## Follow-ups (not in this ticket)

- `go to line <n>` and `command palette <words>` as one phrase, which needs a pattern hook in packs.
- `end debugging` (⇧F5) and other debug toolbar commands (restart, pause).
- VS Code Insiders and the VS Code forks, once NH-80 (installable packs) lands.
