# NH-77: Safari voice commands: Design

**Date:** 2026-11-16  **Ticket:** [NH-77](https://github.com/noahstotland/nohands/issues/77)
**Status:** Draft

## Intent

Safari should answer to spoken control the way the other packed apps do: the user says what they want and Safari does
it, with no keyboard. Half of what the ticket lists already works in Safari through global phrases (`new tab`,
`close tab`, `reload`, `go back`, `zoom in`, `tab 3`, ...). The rest (private window, reopen closed tab, bookmarks,
Reading List, Tab Overview, history, downloads, address bar, view source, print) has no phrase. This ticket adds a
Safari pack (`com.apple.Safari`) on the NH-76 mechanism, the same shape as the Mail and Messages packs: a table file,
one line in the pack registry, a table test and rows in `docs/voice-commands.md`.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance, with the changes listed under Calls I made: the global phrases that
already do the right thing in Safari stay global, and tab by number stays with NH-53's tab reader instead of
command-1 to command-9.

Non-goals (the ticket's Out of scope): Chrome (#74) and Finder (#78), page content actions (clicks, forms), tabs by
title (#53, shipped), and anything in Safari's Develop menu beyond view source.

Anti-goals. Any of these makes the ticket a failure even if the phrases work:

- A Safari phrase changes what a phrase does in another app, or with no app in front.
- A global phrase that already works in Safari (`new tab`, `close tab`, `close window`, `next tab`, `previous tab`,
  `reload`, `go back`, `go forward`, `find`, `zoom in`, `zoom out`, `actual size`, `home`, `tab 3`, `close other tabs`)
  does something different in Safari after this change.
- Any phrase is "stop" or contains "stop", or a stop phrase reaches the pack.
- A phrase closes or quits without saying so, or the built-in pack fails the NH-80 validator round trip.

## What the code forces

- **The pack mechanism exists** (`NoHandsCore/AppPack.swift`). A pack is a `[String: [Action]]` of normalized
  phrases. `CommandGrammar.parse(_:frontmost:)` tries the pack's whole phrase, then the global table, then the pack
  after dropping a leading "open" / "go to" and one article, so "go to the address bar" reaches `address bar` and
  "open a new private window" reaches `new private window`. These lookups run before the tab, file and `go to <site>`
  patterns, so a Safari phrase that starts with `go to` or `open` wins over the address-bar and app-opening patterns
  while Safari is in front. Stop phrases never reach a pack.
- **Built-in packs must survive the NH-80 format.** `builtInPacksRoundTripThroughTheFormat` encodes every pack in
  `AppPacks.all` and parses it back through the validator. So no blocked chord (command-space, command-tab,
  command-option-escape, command-option-delete), no close or quit unless the phrase says so, no irreversible menu
  item, no phrase over 8 words. Adding the pack also makes `safari` a reserved pack id.
- **Global phrases already cover part of the list with Safari's own chords**: `new tab` ⌘T, `close tab` ⌘W,
  `close window` ⇧⌘W, `next tab` ⌃⇥, `previous tab` ⌃⇧⇥, `reload` ⌘R, `go back` ⌘[, `go forward` ⌘], `find` ⌘F,
  `zoom in` ⌘=, `zoom out` ⌘-, `actual size` ⌘0. Each one is what Safari 17's menus show, so the pack does not
  repeat them.
- **Tab by number is NH-53's.** `tab 3`, `first tab`, `last tab` and `switch to tab 3` already parse to
  `.goToTab(.number(n))`, which presses the tab through Safari's Accessibility tab strip. That works for tabs past 9
  and does not depend on Safari's "Use ⌘-1 through ⌘-9 to switch tabs" setting, which sends ⌘1 to the Favorites bar
  when it is off.
- **Safari 17.5's menu titles on this Mac**, read from `Safari.app/Contents/Resources/Base.lproj/MainMenu.nib`: New
  Window, New Private Window, Open Location, Print, Add Bookmark, Show Bookmarks, Show Bookmarks Sidebar, Add to
  Reading List, Show Reading List Sidebar, Show History, Show Downloads, Show Tab Overview, Show Sidebar, Show Reader,
  Show Favorites Bar, Reload Page From Origin, Move Tab to New Window, Merge All Windows. Reopen Last Closed Tab has a
  title that flips between Tab and Window (`reopenLastClosedTabOrWindow:`), and the sidebar, reader, favorites bar
  and Tab Overview titles flip between Show and Hide, so those use their chords. Show Page Source lives in the
  Develop menu, which Safari shows only with "Show features for web developers" on.
- **No phrase may contain "stop"**, so Safari's Stop (⌘.) gets no phrase; `escape` already stops a load.

## Approaches

1. **One pack of chords in its own Core file (chosen).** No menu walk, testable as a table, and each chord is the one
   Safari shows in its menus. Menu items by title only where Safari has no chord (Move Tab to New Window, Merge All
   Windows).
2. **Menu items by title throughout.** Steadier if a user remaps a shortcut, but the Show / Hide titles flip with
   state and every phrase pays the Accessibility walk. Kept as the fallback for a chord the manual check finds broken.
3. **Repeat the global browser phrases in the pack too** (new tab, reload, zoom...). Makes the pack file a complete
   list on its own, but adds nothing a user can hear, and every repeated entry shows in the install summary as an
   overridden NoHands phrase. Not done.

## How it works

### `NoHandsCore/SafariPack.swift`

```swift
extension AppPack {
    static let safari: AppPack = { ... AppPack(name: "Safari", bundleIDs: ["com.apple.Safari"], phrases: phrases) }()
}
```

and `AppPacks.all` gains `.safari` at the end (`[.terminal, .vscode, .mail, .messages, .safari]`). Chrome (#74) and
Finder (#78) add their own neighbours on that line. Phrases (normalized keys):

| Phrases | Action | Safari menu item |
|---|---|---|
| `new window`, `new safari window` | ⌘N | File > New Window |
| `new private window`, `private window`, `private browsing window` | ⇧⌘N | File > New Private Window |
| `reopen closed tab`, `reopen last closed tab`, `reopen tab`, `undo close tab`, `restore tab`, `reopen closed window`, `reopen last closed window` | ⇧⌘T | History > Reopen Last Closed Tab (or Window) |
| `address bar`, `focus address bar`, `open location`, `search bar`, `smart search field` | ⌘L | File > Open Location |
| `bookmark this page`, `bookmark page`, `bookmark this`, `add bookmark` | ⌘D | Bookmarks > Add Bookmark |
| `show bookmarks`, `hide bookmarks`, `bookmarks`, `bookmarks sidebar`, `show bookmarks sidebar` | ⌃⌘1 (toggles) | View > Show Bookmarks Sidebar |
| `edit bookmarks`, `bookmark editor`, `all bookmarks` | ⌥⌘B | Bookmarks > Show Bookmarks |
| `add to reading list`, `save to reading list`, `read later` | ⇧⌘D | Bookmarks > Add to Reading List |
| `show reading list`, `hide reading list`, `reading list` | ⌃⌘2 (toggles) | View > Show Reading List Sidebar |
| `show history`, `history`, `show all history`, `browsing history` | ⌘Y | History > Show History |
| `show downloads`, `downloads`, `safari downloads` | ⌥⌘L | View > Show Downloads |
| `tab overview`, `show tab overview`, `hide tab overview`, `show all tabs`, `all tabs` | ⇧⌘\ (toggles) | View > Show Tab Overview |
| `show sidebar`, `hide sidebar`, `toggle sidebar`, `sidebar` | ⇧⌘L (toggles) | View > Show Sidebar |
| `reader`, `reader view`, `reader mode`, `show reader`, `hide reader` | ⇧⌘R (toggles) | View > Show Reader |
| `favorites bar`, `show favorites bar`, `hide favorites bar`, `favourites bar` | ⇧⌘B (toggles) | View > Show Favorites Bar |
| `hard reload`, `hard refresh`, `reload from origin`, `reload page from origin`, `reload without cache` | ⌥⌘R | Reload Page From Origin |
| `view source`, `view page source`, `show page source`, `page source` | ⌥⌘U | Develop > Show Page Source |
| `print page`, `print this page`, `print the page` | ⌘P | File > Print |
| `home page`, `safari home page` | ⇧⌘H | History > Home |
| `move tab to new window` | `.menuItem("Move Tab to New Window")` | Window > Move Tab to New Window |
| `merge all windows`, `merge windows` | `.menuItem("Merge All Windows")` | Window > Merge All Windows |

The ticket's `close window`, `close tab`, `next tab`, `previous tab`, `tab 1` to `tab 9`, `reload`, `back`,
`forward`, `find`, `zoom in`, `zoom out` and `actual size` are the global phrases, unchanged.

### Expected overlap with the Chrome pack (#74)

Chrome's list is not on main yet. These Safari phrases are the ones I expect #74 to share word for word, so a user
can say the same thing in both browsers: `new window`, `reopen closed tab`, `address bar`, `bookmark this page`,
`show bookmarks`, `show history`, `show downloads`, `view source`, `hard reload`, `print page`,
`move tab to new window`. The chords differ for some (Chrome: downloads ⇧⌘J, bookmarks ⌥⌘B, hard reload ⇧⌘R), which
is why each browser has its own pack. Chrome's `new incognito window` is Safari's `new private window`; I add
`new incognito window` to Safari only if #74 lands first and uses it (Calls). Safari-only: Reading List, Tab
Overview, Reader, sidebar, favorites bar, merge all windows.

### `docs/voice-commands.md`

Rows in the Per-app commands table (App `Safari`), one per group above, and a sentence after the Mail one: the
global browser phrases (`new tab`, `close tab`, `reload`, `go back`, `zoom in`, `tab 3`...) work in Safari as
elsewhere; the sidebar, Reading List, Reader, favorites bar and Tab Overview phrases toggle; `view source` needs
Safari's "Show features for web developers" setting; `reopen closed tab` reopens whatever closed last, tab or
window. The ticket says README; the table moved to `docs/voice-commands.md` in NH-119.

## Tests

Core, table-driven (`SafariPackTests.swift`, no permissions):

- **Safari in front:** a sample phrase from each group, including lead-word forms ("go to the address bar", "open a
  new private window", "open downloads"), resolves to its action through the shipped `CommandGrammar()`, so the
  registry line is tested too.
- **Another app or none in front:** each sampled phrase does not resolve to its Safari action with `com.apple.mail`
  or no app in front.
- **Global phrases unchanged in Safari:** `new tab`, `close tab`, `close window`, `next tab`, `previous tab`,
  `reload`, `go back`, `go forward`, `find`, `zoom in`, `zoom out`, `actual size`, `home`, `tab 3`, `last tab`,
  `close other tabs`, `go to youtube`, `stop`, `cancel` give in Safari what they give with no app in front. No
  Safari phrase is a stop phrase or has "stop" as a word.

The existing `builtInPacksRoundTripThroughTheFormat` and `shippedPacksAreWellFormed` tests cover the validator and
the stop-phrase rule once `.safari` is in `AppPacks.all`.

Manual in Safari 17.5 on macOS 14 (listed in the PR, with any phrase that fails): each phrase through
`nohands-cli parse "<phrase>" --app com.apple.Safari` for the dry run and by voice; `view source` with the developer
setting off and on; `hard reload` with it off; `reopen closed tab` after closing a tab and after closing a window;
`tab 3` with the ⌘1 to ⌘9 setting off.

## Calls I made (surprising first)

- **Tab by number stays NH-53's `tab 3`, not command-1 to command-9.** The ticket asks for the chords, but the global
  `tab 3` already reaches Safari's tabs through Accessibility, works past tab 9, and keeps working when Safari's ⌘1
  to ⌘9 setting is off (then ⌘3 opens the third Favorites bookmark instead). Adding pack phrases would only change
  how the same words act.
- **The global browser phrases are not copied into the pack.** `new tab`, `close tab`, `close window`, `next tab`,
  `previous tab`, `reload`, `go back`, `go forward`, `find`, `zoom in`, `zoom out` and `actual size` already press
  Safari's own chords. The docs row says they work in Safari.
- **Bare nouns `downloads`, `history`, `bookmarks`, `reading list`, `reader`, `sidebar` are phrases.** So `open
  downloads` and `go to history` work in Safari, and they win over the app-opening pattern there: with Safari in front
  `open downloads` shows Safari's downloads, not an app called Downloads. `open the downloads folder` still opens the
  folder (NH-58) because it is not a pack phrase. No bare `print` (a verb), `home` (the Home key stays global) or
  `reload` variants that change the global one.
- **`hard reload` and `view source` are ⌥⌘R and ⌥⌘U.** View source needs Safari's "Show features for web
  developers"; with it off Safari ignores the chord and nothing happens. The docs say so. Hard reload is checked by
  hand with the setting off; if it needs the Develop menu too, the PR says so and the docs row adds the same note.
- **`reopen closed window` is the same ⇧⌘T as `reopen closed tab`.** Safari's one item reopens whatever closed last;
  a separate "Reopen Last Closed Window" title only shows when a window closed last, so a title lookup would fail
  half the time.
- **Show / hide pairs share one toggle chord** (sidebar, bookmarks sidebar, Reading List, Reader, favorites bar, Tab
  Overview), as in Mail and VS Code. `hide reading list` on a hidden list shows it.
- **No phrase for Stop (⌘.)**: no pack phrase may contain "stop". `escape` stops a page load.
- **No `close all windows`, `pin tab` or `mute tab`.** Not in the ticket; close all is a bulk close, and pin and mute
  have titles that flip with state. `menu pin tab` works today.
- **Added synonyms the ticket did not list**: `private window`, `read later`, `restore tab`, `hard refresh`,
  `favourites bar`, `home page`, `move tab to new window`, `merge all windows`, `favorites bar`.
- **`new incognito window` is left to #74.** If Chrome's pack uses it and lands first, the build adds it here as a
  synonym of `new private window` so the two browsers share it; otherwise it is a follow-up.
- **`safari` becomes a reserved pack id**, like `terminal` and `mail`. A user pack installed by hand with that exact
  id would then fail to load until renamed; `pack new` names Safari drafts `com-apple-safari`, so it does not hit
  this.
- **The pack lives in its own file** (`SafariPack.swift`) and only appends `.safari` to `AppPacks.all`, so the Chrome
  and Finder packs don't collide beyond that one line and their own rows in `docs/voice-commands.md`.
- **Chords come from Safari 17.5's menus as Apple documents them**; the nib confirmed the titles but its key
  equivalents can't be read reliably outside Safari. A chord that fails the manual check becomes `.menuItem(<title>)`
  with the titles above, and the PR says which.

## Follow-ups (not in this ticket)

- `new incognito window` as a shared synonym once #74's list is on main, if the build didn't add it.
- Pin and mute tab phrases, if wanted.
