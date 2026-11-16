# NH-74: Chrome voice commands: Design

**Date:** 2026-11-16  **Ticket:** [NH-74](https://github.com/noahstotland/nohands/issues/74)
**Status:** Proposed

## Intent

Chrome is where most hands-free time goes, and today only the handful of global chords (new tab, close tab, reload,
back, find, zoom) reach it. This ticket adds a Chrome app pack on the NH-76 mechanism (`com.google.Chrome`): new and
incognito windows, reopening a closed tab, pinning, duplicating and moving tabs, tab search, hard reload, home page,
find next and previous, view source, developer tools, print, bookmarks, history, downloads, extensions, settings,
deleting browsing data and the address bar. Every phrase works with or without a leading "open" and an article. It is
one table file, one line in the pack list, one test file and rows in `docs/voice-commands.md`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the changes listed under Calls I made.

Non-goals (the ticket's Out of scope): tabs by title or number (NH-53 shipped them), page content, other Chromium
browsers (Brave, Edge, Arc), other apps (NH-77 Safari, NH-78 Finder, NH-79 Mail), and guessing that an unknown app
name is a shortcut.

Anti-goals, which would make this a failure even if it works:

- A Chrome phrase changes what any phrase does in another app, or with no app in front.
- A Chrome phrase changes `open <app>`, `open file <name>` or the NH-58 `open the <words> folder|file|…` phrases,
  in Chrome or anywhere else.
- Any phrase is "stop" or contains "stop", or a stop phrase reaches the pack.
- A global phrase that already does the right thing in Chrome starts doing something else there.
- The built-in pack fails the NH-80 validator (its round trip test), or a phrase deletes, closes or quits something
  its words don't say.

## What the code forces

- **"open a new tab" already works.** NH-76 added `PhraseLead.strip` and, after the pack lookup, a global-table lookup
  on the phrase without an `open` lead when two or more words are left (`CommandGrammar.parse`). So "open a new tab"
  is ⌘T in every app today (`AppPackTests.leadWordsReachTheSameEntry`, `CommandGrammarTests` line 229). The ticket's
  bug report predates that. The parse fix left for this ticket is the Chrome-only phrases: "open a new window" in
  Chrome is still `.openApp("a new window")` ("no app named a new window"), because `new window` is in no table.
  The Chrome pack fixes that and every other "open <chrome phrase>" with no grammar change.
- **Lookup order** (`CommandGrammar.parse`): the front app's pack on the whole phrase, the global table on the whole
  phrase, the pack on the phrase with one leading `open` or `go to` and then one `a` / `an` / `the` dropped, the
  global table after an `open` lead (two or more words), `menu <words>`, tabs (NH-53), text edits, rewrites, media,
  settings panes, then the patterns, where `open` tries the NH-58 file phrases, then a site, then `open <app>`.
  A stop phrase never reaches a pack.
- **How "open <chrome phrase>" is told apart from the other `open` phrases.** The pack is consulted only while Chrome
  is frontmost, and only on an exact match of the whole remaining phrase after one `open` and one article are
  dropped. Nothing is matched by prefix or by guessing. So:
  - `open chrome`, `open safari`, `open notes`: no pack phrase is an app name, so they fall through to `open <app>`
    as before, in Chrome too. The test pins `open chrome` and `open safari` with Chrome in front.
  - `open file budget`, `open the downloads folder`, `open my last keynote`, `open trash`: no pack phrase starts with
    `file`, `my` or `last`, or ends with `folder`, `file`, `document`, `spreadsheet`, `presentation` or `pdf`, and
    none is `trash`. They reach `parseOpenFile` unchanged. The test pins these with Chrome in front.
  - `open downloads`, `open the history`, `open bookmarks`, `open settings`, `open extensions` in Chrome: these are
    pack phrases now, so they open Chrome's page. Before, all five were `open <app>` with that name (`open settings`
    is `.openApp("settings")`, `CommandGrammarTests` line 375). Outside Chrome all five are unchanged.
    `open system settings` and `open settings for <pane>` still open System Settings in Chrome (not pack phrases).
    This is the same trade VS Code made for `open settings`.
  - `home page` is a phrase but `home` is not, so `open home` stays the Home app and `home` stays the Home key.
  - NH-53's tab phrases (`close the other tabs`, `list tabs`, `tab 3`, `switch to the youtube tab`) are not pack
    phrases, so they keep their rule. `duplicate tab` and `pin tab` would never have been tab names anyway (a name
    needs a lead), and `open the duplicate tab` now reaches the pack first.
- **The NH-80 validator applies to built-in packs** through `builtInPacksRoundTripThroughTheFormat`
  (`PackFileTests.swift`): no stop or reserved phrase, `ShortcutGuard` (⌘W and ⌘Q, or a Close or Quit menu item, need
  a close or quit word), blocked chords (⌘ with Space, Tab, ⌥Esc, ⌥⌫, and ⇧⌫ unless the phrase says "empty trash"),
  and `IrreversibleGuard` (a menu item whose title has Delete, Remove, Send, … needs the phrase to say that verb).
  Two consequences:
  - Chrome's ⇧⌘⌫ (Delete Browsing Data) is a blocked chord, so that phrase is the menu item instead.
  - Chrome 157 titles that item **Delete Browsing Data…**, so the phrase must say "delete". "clear browsing data"
    would be held by the irreversible check (see Calls).
- **`shippedPacksAreWellFormed`** already checks every pack in `AppPacks.all` for stop phrases, empty actions and
  unnormalized keys. `.menuItem(title)` searches submenus (`MenuMatch`), so `Extensions` finds Window › Extensions.
- **Chrome 157's macOS menu titles**, read from `en.lproj/locale.pak` in the installed Chrome 157.0.8103.52:
  File: New Tab, New Window, New Incognito Window, Reopen Closed Tab, Open Location, Close Window, Close Tab, Save Page
  As, Print. Edit: Find Next, Find Previous. View: Always Show Bookmarks Bar, Stop, Reload This Page, Force Reload This
  Page, Enter Full Screen, Actual Size, Zoom In, Zoom Out, Developer › View Source, Developer Tools, JavaScript Console.
  History: Home, Back, Forward, Show Full History. Bookmarks: Bookmark Manager, Bookmark This Tab, Bookmark All Tabs.
  Tab: Duplicate Tab, Pin Tab, Move Tab to New Window, Search Tabs. Window: Downloads, Extensions. Chrome: Settings,
  Delete Browsing Data. The `.pak` strings hold no shortcuts, and some titles (Duplicate Tab, Pin Tab, Bookmark
  Manager) appear in other menus' strings too, so the build checks every chord and title against the running app
  (plan step below).
- **Chrome has no menu-bar item to translate a page or to open Reading mode on macOS 157.** Translate is in the page's
  right-click menu and the address bar; "Open in Reading Mode" is in the right-click menu and the side panel.
  `.menuItem` reads only the menu bar.

## Design

A new `Sources/NoHandsCore/ChromePack.swift` holds `AppPack.chrome` in the same shape as `VSCodePack.swift` (groups
of phrases to one action list), and `AppPacks.all` gains `.chrome` at the end. Bundle ID: `com.google.Chrome`.

Phrases (all normalized; the lead-word strip adds the "open …", "go to the …" and "a/the …" forms for free):

| Phrases | Action (Chrome 157, macOS) |
|---|---|
| `new window` | ⌘N |
| `new incognito window`, `incognito window`, `incognito` | ⇧⌘N |
| `reopen closed tab`, `reopen tab`, `reopen last tab`, `restore tab` | ⇧⌘T |
| `duplicate tab`, `duplicate this tab` | menu `Duplicate Tab` |
| `pin tab`, `pin this tab` | menu `Pin Tab` |
| `unpin tab`, `unpin this tab` | menu `Unpin Tab` |
| `move tab to new window`, `move tab to a new window`, `move this tab to a new window` | menu `Move Tab to New Window` |
| `search tabs`, `tab search` | ⇧⌘A |
| `hard reload`, `force reload`, `hard refresh` | ⇧⌘R |
| `home page`, `go home` | ⇧⌘H |
| `find next` | ⌘G |
| `find previous` | ⇧⌘G |
| `view source`, `view page source`, `page source` | ⌥⌘U |
| `developer tools`, `dev tools`, `devtools` | ⌥⌘I |
| `javascript console` | ⌥⌘J |
| `print page`, `print this page` | ⌘P |
| `save page`, `save page as`, `save this page` | ⌘S |
| `bookmark this page`, `bookmark this tab`, `bookmark page`, `add bookmark` | ⌘D |
| `bookmark all tabs` | ⇧⌘D |
| `bookmarks bar`, `show bookmarks bar`, `hide bookmarks bar`, `toggle bookmarks bar` | ⇧⌘B |
| `bookmark manager`, `bookmarks`, `manage bookmarks` | ⌥⌘B |
| `history`, `show history`, `browsing history` | ⌘Y |
| `downloads`, `show downloads` | ⇧⌘J |
| `delete browsing data` | menu `Delete Browsing Data…` |
| `extensions`, `show extensions`, `manage extensions` | menu `Extensions` |
| `settings`, `chrome settings`, `preferences` | ⌘, |
| `address bar`, `focus address bar`, `location bar`, `url bar` | ⌘L |

Already global and right in Chrome, so not repeated: `new tab` ⌘T, `close tab` ⌘W, `close window` ⇧⌘W, `next tab`
⌃Tab, `previous tab` ⌃⇧Tab, `reload` / `refresh` ⌘R, `go back` ⌘[, `go forward` ⌘], `find` ⌘F, `zoom in` ⌘=,
`zoom out` ⌘-, `actual size` / `reset zoom` ⌘0, `full screen` ⌃⌘F, `save` ⌘S, `escape` (stops a page load).

Close and discard: `close tab` and `close window` stay the global phrases, and the task loop's `ShortcutGuard` still
blocks ⌘W from a model step whose goal has no close word; nothing here changes that. `delete browsing data` opens
Chrome's dialog and presses nothing in it.

Verification in the build: with Chrome 157 running, read each pack chord's menu item and its key equivalent through
Accessibility (`MenuShortcutReader` / `AXMenuReader`, as a one-off check, not a unit test), and each `.menuItem`
title. A chord that doesn't match its menu becomes the right chord, or the menu item when it has none. A phrase that
can't be made to work is dropped and listed in the PR's Not proven list.

## Tests

`Tests/NoHandsCoreTests/ChromePackTests.swift`, table-driven like `VSCodePackTests`:

1. Every shipped Chrome phrase, as is, with `open `, with `open a ` / `open the `, parses to its action with Chrome in
   front, and is not that action with Safari in front or no app in front (so `bookmark this page` in Safari does not
   run the Chrome action).
2. In Chrome: `open chrome` and `open safari` are `.openApp`; `open file budget`, `open the downloads folder`,
   `open my last keynote`, `open system settings`, `close the other tabs`, `tab 3`, `stop`, `cancel` parse as they do
   with no app in front.
3. No Chrome phrase contains "stop".

The validator and well-formedness come from the existing `builtInPacksRoundTripThroughTheFormat` and
`shippedPacksAreWellFormed`, which run over `AppPacks.all`.

Manual, listed in the PR (needs Chrome and Accessibility): in Chrome 157 on macOS 14, "open a new tab" opens a tab
with no "no app named" message, "open a new window" opens a window, and each other phrase does what it says.

## Docs

`docs/voice-commands.md` § Per-app commands: Chrome rows after the Messages rows, and one paragraph under the table
on the globals that also work in Chrome, `escape` for stopping a load, `open settings` meaning Chrome's settings
there, and `delete browsing data` opening the dialog only.

## Calls I made

- **`clear browsing data` is not a phrase; it is `delete browsing data`.** The ticket names "clear browsing data", but
  Chrome 157's item is titled Delete Browsing Data…, its chord ⇧⌘⌫ is blocked by the NH-80 validator, and the
  irreversible guard holds a Delete menu item unless the phrase says "delete". Loosening the guard is out of scope.
  "clear browsing data" goes to the model as before, which asks before pressing it.
- **No `stop loading` phrase.** No pack phrase may contain "stop" (the VS Code rule, so a spoken stop is never
  mistaken for a command). `escape` already stops a page load in Chrome; the docs say so.
- **Translate this page and Reading mode are left out.** Chrome 157 has no menu-bar item for either; the ticket
  scopes translate to "where Chrome has a menu item". The build checks again and adds them only if an item exists.
- **`open settings`, `open downloads`, `open history`, `open bookmarks`, `open extensions` open Chrome's pages while
  Chrome is in front.** They were `open <app>` with that name there before; `open system settings` still opens
  System Settings.
- **No bare `back`, `forward` or `print`.** A one-word phrase fires before the rest of a sentence arrives; `go back`,
  `go forward` and `print page` cover them. `incognito`, `history`, `downloads`, `bookmarks`, `extensions` and
  `settings` are bare because they are nouns that don't start a longer command.
- **`home page` and `go home`, not `home`**, so the Home key and `open home` (the Home app) keep working.
- **Pin and unpin are two phrases with two titles** (Chrome flips the menu title), not one toggle.
- **Chrome only (`com.google.Chrome`)**, not Beta, Canary or other Chromium browsers, per the ticket.
- **Chords where Chrome has one, menu items for Duplicate, Pin, Unpin, Move to New Window, Delete Browsing Data and
  Extensions**, which have no default chord. Every chord and title was read from the running Chrome 157's menu bar
  through Accessibility (Downloads is ⇧⌘J there).
- **No grammar change.** The "open a new tab" fix already shipped in NH-76; this ticket only adds the pack, which keeps
  the diff to Chrome files plus one line in `AppPacks.all` and the docs rows, so NH-77 and NH-78 merge with little
  conflict.
- **`docs/app-packs.md` is not touched.** Its "ships a Terminal pack" and reserved-id lines are already stale for Mail,
  VS Code and Messages; fixing them for every pack is a separate docs change.
