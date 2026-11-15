# NH-84: Terminal voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-84](https://github.com/noahstotland/nohands/issues/84)
**Status:** Shipped
**Shipped:** in PR #138, as specified

## Intent

Terminal's window, tab, scrollback and font commands are chords, so today they can't be said at all, apart from the
global tab and window phrases. This ticket ships the first app pack on the NH-76 mechanism: Terminal
(`com.apple.Terminal`), with phrases for new window, clear, scroll to top or bottom, split pane, font size and
interrupt (control-C). It is a table file, a line in the pack registry, a test and README rows.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals (the ticket's Out of scope): speaking or typing shell commands, pressing return for the user (the global
`enter` covers it), other terminal apps (iTerm2, Ghostty, Warp), answering Terminal's own "close with a running
process?" sheet.

Anti-goals, which would make this a failure even if it works:

- A Terminal phrase changes what a phrase does in any other app, or with no app in front.
- Any phrase is "stop" or contains "stop", or a stop phrase reaches the pack.
- "interrupt" or "cancel command" is taken as a NoHands stop, or "cancel" / "cancel that" stops being one.
- A phrase types text into the shell or runs a command.

## What the code forces

- **The pack mechanism exists** (`NoHandsCore/AppPack.swift`, NH-76). `AppPacks.all` is empty; a pack is a
  `[String: [Action]]` of normalized phrases to chords or `.menuItem(title)`. `CommandGrammar.parse(_:frontmost:)`
  checks the pack after a whole-phrase global hit unless the pack has the same phrase, drops a leading "open",
  "go to" and an article before the pack lookup, and never sends a stop phrase to a pack.
  `shippedPacksAreWellFormed` (`AppPackTests.swift`) already rejects stop phrases, empty actions and unnormalized
  keys in shipped packs.
- **The global table already covers five of the ticket's phrases** with the chords Terminal uses: `new tab` (⌘T),
  `close tab` (⌘W), `close window` (⇧⌘W), `next tab` (⌃Tab), `previous tab` (⌃⇧Tab), plus `find` (⌘F) and
  `page up` / `page down` (the plain keys, which Terminal turns into scrollback paging outside full-screen programs
  and passes to `less` or `vim` inside them). The pack does not repeat them.
- **"scroll to top" today goes to the model** (`parseFind` with `edgesAreWords: false` declines page edges), so a pack
  entry takes it in Terminal without changing other apps.
- **`StopWords.isStop`** treats a phrase as a stop only when every word is a stop word or a filler; "cancel command"
  and "interrupt" are not stops, and "cancel" alone stays one (it never reaches a pack).
- **Terminal's menu titles and shortcuts on macOS 14.5**, read from Terminal's own `MainMenu.nib` and
  `MainMenu.loctable` on this machine:

  | Menu item | Shortcut |
  |---|---|
  | New Window (default profile) | ⌘N |
  | Clear to Start | ⌘K |
  | Clear Scrollback | ⌥⌘K |
  | Clear Screen | ⌃⌘L |
  | Scroll to Top / Scroll to Bottom | ⌘Home / ⌘End |
  | Split Pane / Close Split Pane | ⌘D / ⇧⌘D |
  | Bigger / Smaller / Default Font Size | ⌘+ / ⌘- / ⌘0 |

  Every phrase therefore gets a chord; none needs a `menuItem`.

## Approaches

1. **One pack of chords in its own Core file (chosen).** Fast (no menu walk), testable as a table, and each phrase
   matches a shortcut Terminal shows in its menus.
2. **Menu items by title** (`.menuItem("Clear Scrollback")`). Survives a user remapping a shortcut, but every phrase
   pays the Accessibility menu walk, and titles change by language. Kept as the fallback for any chord the manual check
   finds broken.
3. **Typing `clear` and return into the shell.** Types into the running program, which the ticket rules out.

## How it works

### `NoHandsCore/TerminalPack.swift`

```swift
extension AppPack {
    static let terminal = AppPack(name: "Terminal", bundleIDs: ["com.apple.Terminal"], phrases: [ ... ])
}
```

and `AppPacks.all = [.terminal]`. Phrases (normalized keys):

| Phrases | Action |
|---|---|
| `new window`, `new terminal window` | ⌘N |
| `clear`, `clear all`, `clear terminal` | ⌘K (Clear to Start: screen and scrollback) |
| `clear screen` | ⌃⌘L (Clear Screen) |
| `clear scrollback`, `clear the scrollback`, `clear history` | ⌥⌘K (Clear Scrollback) |
| `scroll to top`, `scroll to the top` | ⌘Home |
| `scroll to bottom`, `scroll to the bottom` | ⌘End |
| `split pane`, `split window`, `split the window` | ⌘D |
| `close pane`, `close split pane`, `close the split pane` | ⇧⌘D |
| `bigger font`, `font bigger`, `increase font size`, `bigger text`, `make text bigger`, `make the text bigger`, `larger text` | ⌘⇧= (the `+` key) |
| `smaller font`, `font smaller`, `decrease font size`, `smaller text`, `make text smaller`, `make the text smaller` | ⌘- |
| `default font size`, `reset font size`, `normal font size` | ⌘0 |
| `interrupt`, `interrupt command`, `cancel command`, `send control c` | ⌃C |

With the lead stripping from NH-76, "open a new window" and "a new window" reach the `new window` entry. "go to the
bottom" does not, since there is no `bottom` entry (see Calls).

### README

Rows in the Per-app commands table (App `Terminal`): one row per group above, plus a sentence noting that the
global `new tab`, `close tab`, `close window`, `next tab`, `previous tab`, `find`, `page up` and `page down` also
work in Terminal, that closing a tab or window with a running command shows Terminal's own confirm, and that
"stop" never interrupts a shell command (say "interrupt").

## Tests

Core, table-driven (`TerminalPackTests.swift`, Core only, no permissions):

- **Terminal in front:** every phrase in the table above, plus the global phrases the ticket lists (`new tab`,
  `close tab`, `close window`, `next tab`, `previous tab`, `find`, `page up`, `page down`), resolves to its chord,
  using the shipped `CommandGrammar()` (so the registry line is tested too).
- **Another app or none in front:** each pack-only phrase does not resolve to its Terminal chord with
  `com.apple.Safari` or no app in front.
- **No stop:** no Terminal phrase is a stop phrase or has "stop" as a word; "stop", "cancel" and "cancel that" with
  Terminal in front still give what they give with no app in front.
- The existing `shippedPacksAreWellFormed` now runs over a real pack.

Manual on macOS 14 (listed in the PR, with any phrase that fails): each phrase with Terminal in front, through
`nohands-cli parse --app com.apple.Terminal "<phrase>"` for the dry run and by voice in the app; "interrupt" during
`sleep 30`; "close window" with a running command shows Terminal's sheet and nothing answers it.

## Calls I made

- **Bare "clear" is ⌘K (Clear to Start), the clear most Mac users know, and wipes scrollback too.** "clear screen"
  is Terminal's own Clear Screen (⌃⌘L) and "clear scrollback" its Clear Scrollback (⌥⌘K), named after the menu items.
- **"cancel command" is a phrase** (the ticket asks for it) even though "cancel" alone is a NoHands stop word. It
  is not a stop by `StopWords` rules, and bare "cancel" never reaches the pack.
- **`page up` / `page down` stay the global plain keys**, not Terminal's ⌘PageUp / ⌘PageDown menu items, so they
  still page inside `less`, `man` and `vim`. The ticket's "page up, page down" are covered by the global phrases.
- **No pack entries for phrases the global table already maps to the same chord** (new tab, close tab, close
  window, next tab, previous tab, find). The test still checks them with Terminal in front.
- **Every phrase is a chord, none a menu item**, because Terminal has a shortcut for each one (read from its menu
  file on macOS 14.5). A chord that fails the manual check switches to `.menuItem(<title>)` with the titles in the
  table above, and the PR says which.
- **Bigger font is ⌘⇧= (what the `+` key sends on a US layout)**, not ⌘=, since Terminal's menu shortcut is ⌘+.
  The manual check confirms it; the fallback is `.menuItem("Bigger")`.
- **Added a few synonyms the ticket did not list** ("new terminal window", "clear history", "split window", "bigger
  text", "make text bigger", "send control c", "interrupt command"). No bare `top` or `bottom` entries, so
  "go to the top" and "top" keep their current meaning.
- **The pack lives in its own file** (`TerminalPack.swift`) so later app tickets don't edit the same table.
- **The pack does not answer Terminal's close confirm sheet**, as the ticket says; the user can say "enter" or
  "escape".

## Follow-ups (not in this ticket)

- Saying or typing shell commands, behind #61's confirm step.
