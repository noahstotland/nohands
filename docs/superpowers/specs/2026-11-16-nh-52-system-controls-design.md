# NH-52: System controls by voice: Design

**Date:** 2026-11-16  **Ticket:** [NH-52](https://github.com/noahstotland/nohands/issues/52)
**Status:** Proposed

## Intent

A keyboard-free Mac still needs its system chores done: lock the screen before walking away, take a screenshot,
look at every window, switch Spaces, open the Bluetooth pane. None of these has a voice phrase today, so each one
goes to the model (or does nothing with the model off) or needs hands.

## Goals, non-goals, anti-goals

Goals: the ticket's Scope and Acceptance, with the changes listed under Calls I made.

Non-goals: dark mode and Do Not Disturb (see Dark mode and Do Not Disturb below); Wi-Fi, Bluetooth and other
Control Center toggles (ticket out of scope); volume and mute (shipped in #51); giving the model new action kinds or
letting it open `x-apple.systempreferences:` URLs; a spoken yes before "empty trash" (that is NH-149).

Anti-goals, which would make this a failure even if it works:

- "empty trash" erases the Trash with no confirm anywhere.
- A system phrase touches the network or the model.
- An existing phrase changes meaning: `space` is still the space key, `spotlight` is still command-space,
  `open system settings` still opens System Settings, `open settings` still opens VS Code's settings while VS Code
  is in front, `hide` still hides the overlay.
- "stop" matches a system phrase, or a system phrase is merged with "stop".
- An unknown pane name ("open settings for slack") opens the wrong pane or the wrong app on a guess.

## What the code forces

- **The grammar's exact table** (`CommandGrammar.exact`) is checked right after pack phrases, and the
  filler-stripped lookup at the end catches "lock the screen", "take a screenshot" and "empty the trash". Fixed
  phrases go there; the pane phrases need a small rule before `parsePattern`, like `parseTab`, because
  `parsePattern`'s `open` rule would otherwise make "open bluetooth settings" an `openApp` that fails.
- **Lock and screenshots are plain chords** (control-command-Q; command-shift-3 and -4), which `pressKey` already
  posts on the HID tap, where the WindowServer takes them before any app.
- **Spaces need more than a chord.** A hardware arrow key carries the fn and numeric-pad flags, and the Spaces
  hotkeys (control-left and control-right) are registered with them; `CGEventInputSynthesizer.press` sets neither,
  so a plain `pressKey` of control-arrow is likely ignored by the Dock. The executor posts it with those flags.
- **Mission Control and Show Desktop** have chords the user may have changed or that collide with brightness keys
  (control-up, F11). `/System/Applications/Mission Control.app` opens Mission Control on every launch, and with the
  argument `1` shows the desktop, whatever the shortcuts are.
- **Notification Center has no default shortcut.** On macOS 14 it opens by pressing the clock in the menu bar,
  which is Control Center's `com.apple.menuextra.clock` item and can be pressed through Accessibility (which
  NoHands already has).
- **Settings panes open from URLs**: `x-apple.systempreferences:<pane id>` through `AXQuery.open(url:appNamed:)`,
  the same path `.openURL` takes. `WebAddress` and `PackFile` only allow web URLs for the model and packs; the
  grammar builds these URLs itself from a fixed table, so neither check is involved.
- **#61's confirm covers task steps only.** `IrreversibleGuard` runs inside `TaskRunner` on steps the model chose;
  a grammar phrase is the user's own words and is never held (the #61 spec and `docs/tasks.md` say so). There is
  no pipeline step that holds a fixed phrase for a spoken yes; NH-149 proposes one.
- **`ShortcutGuard`** blocks a model step that presses command-Q unless the goal says quit, exit or shut, so a
  model step could not press control-command-Q (lock) either. The grammar is not guarded, which is right for words
  the user said.

## Approach

**One grammar-only action, `.system(SystemCommand)`, with the pane table in Core (chosen).** Core gets a
`SystemCommand` enum (`lockScreen`, `screenshot(ScreenshotKind)`, `missionControl`, `showDesktop`,
`space(Direction)`, `notificationCenter`, `openSettings(SettingsPane)`, `emptyTrash`), a `SettingsPane` table
from spoken names to pane ids, and the phrases in the grammar. `ActionExecutor` runs each command in a small
`runSystem` like `runMedia`. The model's schema and decoder do not change, so the model can't emit it, like
`.media` and `.volume`.

Rejected: chords only through `.pressKey` (Spaces and Show Desktop would be unreliable, Notification Center and
empty trash have no safe chord); an AppleScript bridge (needs Automation permission for every command).

### Phrases

| Say | Does |
|---|---|
| `lock screen`, `lock the screen`, `lock computer`, `lock the mac` | Control-command-Q |
| `screenshot`, `take a screenshot`, `screenshot screen` | Command-shift-3: the whole screen, saved where macOS saves screenshots |
| `screenshot selection`, `screenshot area` | Command-shift-4: the crosshair; drag with `hold click`, `move …`, `release click`, or `escape` |
| `screenshot window` | Command-shift-4, then space: the camera pointer; `click` takes the window under the pointer, `escape` cancels |
| `mission control` | Opens Mission Control |
| `show desktop` | Shows the desktop (again: puts the windows back) |
| `next space`, `previous space` | Control-right and control-left with hardware arrow flags |
| `notification center`, `notification centre`, `show notifications` | Presses the menu-bar clock |
| `open settings for <pane>`, `open <pane> settings`, `<pane> settings` | Opens that System Settings pane |
| `empty trash`, `empty the trash` | Finder's Empty Trash… menu item, which shows Finder's own confirm (see below) |

Panes and their spoken names: Wi-Fi (`wifi`, `wi-fi`, `wi fi`), Bluetooth, Sound (`sound`, `audio`), Displays
(`display`, `displays`), Accessibility, Privacy (`privacy`, `privacy and security`, `security`), Login Items
(`login items`, `startup items`), Notifications, Battery, General. Pane ids are the macOS 14 extension ids (for
example `com.apple.BluetoothSettings`, `com.apple.wifi-settings-extension`); the plan's manual check opens each.

An unknown name after `open settings for` ("open settings for slack") is the grammar's own phrase: the row says
`no settings pane called slack: say open system settings` through `CommandGrammar.rejection`, and nothing opens and
nothing goes to the model. `open <x> settings` with an unknown `<x>` keeps today's behaviour (an app named that).

### How "empty trash" stays confirmed

#61 does not cover a fixed phrase, and NH-149 (a spoken yes for fixed phrases) is still open. Until then the
confirm is Finder's own: NoHands brings Finder to the front and presses the menu item `Empty Trash…` (the one with
the ellipsis, which asks), never `Empty Trash` with option held and never the command-option-shift-delete chord.
Finder then shows "Are you sure you want to permanently erase the items in the Trash?", and the user answers
`enter` or `escape`, as with Messages' `delete conversation` (#82). NoHands does not answer it.

Finder skips that question when its setting "Show warning before emptying the Trash" is off. So before pressing,
the executor reads Finder's `WarnOnEmptyTrash` preference; when it is explicitly `false`, nothing is pressed and
the row says `Finder's Trash warning is off: turn it on in Finder Settings > Advanced, or empty the Trash by hand`.
A missing key is the default (on). A disabled menu item says `the Trash is already empty`. When NH-149 lands,
`empty trash` is one of the phrases it marks, and the Finder check can stay as a second net.

### OS-level chords

Every chord here is a system hotkey the WindowServer or Dock handles, not an app shortcut, and the user can
rebind or turn it off in System Settings > Keyboard > Keyboard Shortcuts: control-command-Q (Lock Screen),
command-shift-3 and command-shift-4 (screenshots), control-left and control-right (Spaces). Command-shift-4 is not
a launcher, but none of these is something a pack phrase should be able to press silently; they are global
phrases only. A rebound shortcut makes the phrase do nothing, and the docs row says so. None of them is an app
switcher or launcher like `spotlight` (command-space), which the NH-80 pack validator blocks; that rule is not
changed or relied on here. Posting them is not a global key hook: nothing captures input from other apps.

### Dark mode and Do Not Disturb

Left out, with the reason recorded in the PR. Dark mode has no public API and needs an Apple Event to System
Events, which means a new Automation permission prompt, an `NSAppleEventsUsageDescription`, a permission line in
the onboarding and a failure line naming the fix: its own ticket. Focus and Do Not Disturb have no public API on
macOS 14 at all; the only route is `shortcuts run` on a shortcut the user builds by hand. I file one follow-up
ticket for dark mode at PR time and note Focus in it.

## Testing

Per `AGENTS.md` § Testing:

- One grammar table test: each new phrase (and a filler form) to its action, plus the unchanged phrases from the
  anti-goals (`space`, `spotlight`, `open system settings`, `open settings` with VS Code in front, `hide`, `stop`).
- One pane table test: every spoken name to its pane, and unknown names (`slack`, empty, `settings`) to nil and to
  the rejection line.
- One pure test for the empty-trash decision (warning on, off, missing) if it lives in Core as a function of the
  preference value; otherwise it is a manual check.
- Manual on macOS 14, listed in the PR: each phrase does what it says, each pane opens, `next space` moves with two
  Spaces, `empty trash` shows Finder's question with the warning on and refuses with it off.

## Docs

- `docs/voice-commands.md`: the rows above, the pane list, the empty-trash confirm, and a note that a rebound
  system shortcut makes its phrase do nothing.
- `docs/superpowers/specs/2026-11-04-nohands-design.md` only if the documenter finds the action list stale.

## Calls I made

- **"empty trash" relies on Finder's own confirm and refuses when Finder's warning is off.** The ticket says
  confirm with #61, but #61 holds only model steps; NH-149 is the real fix and stays separate.
- **"screenshot window" needs a spoken `click`.** Command-shift-4 then space leaves the camera pointer on the window
  under the pointer; capturing the front window directly would need Screen Recording rules and its own file naming.
- **Mission Control and Show Desktop launch Mission Control.app** instead of pressing control-up and F11, so they
  work whatever the shortcuts are.
- **Notification Center presses the menu-bar clock through Accessibility**; macOS 14 has no shortcut for it.
- **Spaces post control-arrow with the fn and numeric-pad flags** in the executor, not by changing every arrow press.
- **An unknown pane after "open settings for" is rejected on-device** with a line naming the fix, instead of going
  to the model or opening System Settings at its last pane.
- **Extra spoken forms** beyond the ticket: `lock computer`, `lock the mac`, `take a screenshot`,
  `screenshot screen`, `screenshot area`, `notification centre`, `show notifications`, and the pane aliases above.
- **Dark mode and Do Not Disturb are left out**; one follow-up ticket for dark mode with the Automation permission.
- **The model gets nothing new**: `.system` is grammar-only like `.media` and `.volume`.
