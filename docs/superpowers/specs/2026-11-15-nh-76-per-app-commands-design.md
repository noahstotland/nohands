# NH-76: Per-app voice commands: Design

**Date:** 2026-11-15  **Ticket:** [NH-76](https://github.com/noahstotland/nohands/issues/76)
**Status:** Proposed

## Intent

The grammar has one global phrase table, so "new tab" is command-T in every app and the frontmost app can't bring
its own phrases. Menu commands ("Bookmark This Tab…") can't be said at all without agent-desktop. This ticket adds
the two mechanisms every app ticket (#74 and the ones linked from it) builds on: a **pack** (a phrase table for one
or more bundle IDs, checked before the global table) and **menu items by name** ("menu bookmark this tab"), pressed
natively through Accessibility. It ships no app packs; each app ticket is then a table file and README rows.

## Goals, non-goals, anti-goals

Goals are the ticket's Scope and Acceptance.

Non-goals (the ticket's Out of scope): the packs for specific apps; offering `menu_item` to the model in the native
task loop; a user-editable pack file in the config.

Anti-goals, which would make this a failure even if it works:

- A pack phrase changes what a phrase does in any app other than the pack's.
- A global phrase or pattern changes meaning with no pack in front (apart from the one `open` change below).
- "menu <words>" presses an item the user did not name: a fuzzy guess, or something in the Apple menu
  ("Shut Down…", "Log Out…").
- The menu walk opens a menu on screen, runs on every command, or slows the grammar fast path.
- A spoken "stop" is matched by a pack or merged with a pack phrase.
- Ordinary commands touch the network, or `swift test` needs Accessibility.

## What the code forces

- **`Action.menuItem(String)` already exists.** The model's `menu_item` kind decodes to it (`IntentDecoder`), the
  schema offers it only in the agent-desktop prompt (`IntentSchema.harnessKinds`), `IrreversibleGuard` already reads
  its name, and the executor (`ActionExecutor+Harness.swift`) runs it only through agent-desktop, else
  "needs agent-desktop". The grammar can emit the same action; the executor gains a native path.
- **`CommandGrammar.parse(_:)` takes only the transcript**, and four callers use it: `ModeMachine.routeCommand`,
  `VoicePipeline.isComplete` / `carriesSpokenText` (the merge buffer's early close), `EndpointReplay` and the CLI.
- **`parsePattern` turns `open <x>` into `.openApp(x)`** before the exact table sees the rest, which is #74's bug:
  "open a new tab" opens an app called "a new tab".
- **`AXQuery` never descends into menus** (it collects menu bar items only), so the menu tree needs its own walk.
- **`VoicePipeline` is `@MainActor`**, so it can read `NSWorkspace.shared.frontmostApplication` at routing time.
  The merge buffer's checks are nonisolated closures, so they need the bundle ID handed to them.

## Approaches

1. **Packs as Core tables passed into `CommandGrammar`, frontmost bundle ID as a `parse` argument; native menu walk
   behind a protocol (chosen).** Pure tables, table-driven tests, no AppKit in Core, a fake menu provider in tests.
2. **Packs keyed by app name** ("Google Chrome"). Names are localized and change; bundle IDs don't.
3. **Menu items through agent-desktop only** (today's path). Needs the harness, which the voice path usually lacks,
   and its click opens the menu on screen.

## How it works

### Packs (`NoHandsCore/AppPack.swift`)

```swift
public struct AppPack: Sendable {
    public let name: String                 // "Chrome", for README and logs
    public let bundleIDs: Set<String>
    public let phrases: [String: [Action]]  // keys already normalized: lowercase, single spaces
}
public enum AppPacks { public static let all: [AppPack] = [] }   // app tickets add entries
```

An entry is the same shape as a `CommandGrammar.exact` entry: chords, or `.menuItem(title)`. `CommandGrammar` takes
`packs: [AppPack] = AppPacks.all` in its init (tests inject their own). A pack whose phrases include a stop word is
rejected by a test over `AppPacks.all` (a stop must always reach the stop path).

### Lookup order in `parse(_ transcript:, frontmost bundleID: String? = nil)`

1. Global exact table on the whole phrase (unchanged; "go to sleep", "find" stay first). Exception: when the
   frontmost app's pack has the phrase, the pack wins, so a pack can override a global phrase for its app only.
2. **Pack lookup** for the frontmost bundle ID, on the phrase after the shared normalization below.
3. **"menu <words>"** becomes `[.menuItem(words)]` in any app (raw words, so "Save As…" punctuation from ASR is
   kept for the matcher).
4. Global exact table on the shared normalization, **only when the stripped lead was "open"**: "open a new tab" is
   command-T everywhere. "go to <x>" keeps its meaning (a site, or the address bar) unless a pack has `<x>`.
5. Patterns (`parsePattern`), then the filler-stripped exact match, as today. An unknown "open <x>" still becomes
   `.openApp(x)`.

With `bundleID` nil (CLI default, tests) steps 1 to 5 run with no pack, which is exactly today's behaviour plus
steps 3 and 4.

### Shared normalization (`PhraseLead.strip`)

On the normalized tokens: drop one leading "open" or "go to", then leading "the", "a" or "an". "open a new tab",
"go to the downloads" and "new tab" give "new tab", "downloads", "new tab". It returns the stripped phrase and which
lead it dropped (step 4 needs that). Empty after stripping means no match.

### Menu title matcher (`NoHandsCore/MenuMatch.swift`)

Input: the spoken words and a list of `MenuEntry { title, path: [String], enabled }` in menu bar order. Both sides
are compared after folding: lowercase, "…" and "..." removed, other punctuation dropped, whitespace collapsed.

1. **Exact:** the folded title equals the folded words.
2. **Closest:** titles whose words start with the spoken words, then titles that contain every spoken word as a
   whole word. Within a tier the shortest title wins, then menu bar order.
3. Otherwise no match. There is no edit-distance guess.

A spoken path ("file > save as", from the model) limits the search to that top menu and matches the last part.
The result is the entry (enabled or not); the executor says what to do with a disabled one.

### Native menu path (`NoHandsMac`)

- `MenuReading` protocol: `entries() -> [MenuEntry]` with an opaque handle per entry, and `press(handle) -> Bool`.
  `AXMenuReader` walks the frontmost app's `kAXMenuBarAttribute` children, then each menu's `AXMenu` children
  recursively (submenus included, separators and empty titles skipped), reading `kAXTitleAttribute` and
  `kAXEnabledAttribute`. It **skips the first menu bar item (the Apple menu)**. Budget like the other walks: 200 ms
  and 1500 items; it runs only when a `menuItem` action executes.
- `ActionExecutor` `.menuItem(name)`: native first. Match, then disabled → "menu item <title> is disabled"; matched
  and enabled → `AXPress` (the menu does not open on screen); no match → agent-desktop's find when a harness is
  present (today's path), else **"no menu item called <words>"**.
- `VoicePipeline` passes `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` to `modeMachine.route` and,
  through a value it updates on app activation, to the merge buffer's `isComplete` / `carriesSpokenText` closures,
  so a pack phrase closes the merge window early like a global one.
- **Before building on it** (first build task): check on macOS 14 that `AXPress` on an item in a closed menu runs it
  in Chrome, Safari, Finder and Mail, with a throwaway `nohands-cli menu "<title>"` run. If an app ignores it, that
  app's future pack uses its chord; the result goes in the PR's Proof section.

### CLI

- `nohands-cli parse "<text>" [--app <bundle id>]`: dry run with that app in front.
- `nohands-cli menu "<words>"`: prints the frontmost app's match (title, path, enabled) and presses it after 2 s.
  `nohands-cli menu --list` prints the menu tree. Both are dev tools for the manual check and future pack authors.

### README

The voice command table gets a `menu <words>` row, and a new "Per-app commands" subsection under Voice commands
with a table (App, Say, Does) that app tickets add rows to. It starts empty with one sentence on how packs work. The
CLI table gets `parse --app` and `menu`.

## Tests

Core (table-driven, one test per rule):

- Pack precedence: a pack phrase runs only for its bundle IDs, overrides a global phrase there, and with another
  app (or none) in front the global phrase runs.
- Shared normalization: "open a new tab", "new tab", "go to the new tab" resolve the same in a pack app; "open a new
  tab" is command-T with no pack; unknown "open notes" is still `.openApp("notes")`; "go to youtube" still opens
  the site.
- "menu <words>" becomes `.menuItem`; bare "menu" is no match (goes on to the model as today).
- No pack in `AppPacks.all` has a stop-word phrase or an empty action list.
- Menu matcher: exact, case and ellipsis folding, starts-with tier, contains-all tier, shortest wins, path limits
  the menu, no match, disabled entry returned as disabled.

Mac (fake `MenuReading`, no Accessibility): `menuItem` presses the matched handle; a missing item reports
"no menu item called …"; a disabled one reports disabled and presses nothing.

Manual (listed in the PR): "menu bookmark this tab" in Chrome and "menu new folder" in Finder on macOS 14, plus the
`AXPress` check above in all four apps.

## Calls I made

- **The native menu path is used for every `.menuItem`, including the model's.** The model is still offered
  `menu_item` only in the agent-desktop prompt (no schema or prompt change), but where it already sent one it now
  runs natively first. The alternative, a grammar-only action, doubles the action for no safety gain:
  the irreversible guard already checks `menuItem` names.
- **The Apple menu is never searched**, so "menu shut down" or "menu log out" find nothing. App menus ("Quit
  Chrome") are searched, like the existing "quit app".
- **"Closest match" means starts-with, then contains-every-word, never edit distance**, so a misheard word fails
  with "no menu item called …" instead of pressing a neighbour.
- **"open" + a global phrase now runs the global phrase everywhere** ("open a new tab" is command-T in any app, as
  is "open spotlight"); "go to" + a global phrase does not, because "go to <x>" already means a site or the address
  bar. Without this, #74's bug stays for every app without a pack.
- **The registry ships empty.** Tests use their own packs; Chrome's pack is #74.
- **Global exact phrases win over packs except when the pack has the same phrase**, so a pack can override
  "new tab" for its app but a pack can't shadow "go to sleep" unless it names it on purpose. Stop words are kept
  out of packs by a test, not by code.
- **Pack phrases close the merge window early** like global ones, via the bundle ID the pipeline keeps on app
  activation.
- Two small CLI additions (`parse --app`, `menu`) to make the manual check and later pack work possible without the
  microphone.
- A disabled match fails with "menu item <title> is disabled" rather than trying the next match.
- Walk budget 200 ms / 1500 items; the walk runs only when a menu action executes.

## Follow-ups (not in this ticket)

- `ShortcutGuard` does not look at `menuItem` titles ("Close Window", "Quit …") from the model. That gap exists
  today under agent-desktop; worth its own ticket before the native task loop is offered `menu_item`.
