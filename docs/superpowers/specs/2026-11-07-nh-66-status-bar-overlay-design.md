# NH-66: Always-on status bar overlay — Design

**Date:** 2026-11-07  **Status:** Proposed  **Ticket:** [NH-66](https://github.com/noahstotland/nohands/issues/66)

## Intent

The prompt board shows up only while prompts are live and is empty when NoHands is idle, so "is it listening?"
can only be answered by opening the menu. A small one-line status bar stays on screen and always says what
NoHands is doing: listening, the running task and its step, paused, asleep, loading, or the problem and its fix.
It is on by default, and a **Status Bar** submenu turns it off or moves it to the bottom.

## What the bar says

One pure function in `NoHandsCore` picks the line:

```swift
public struct StatusLine: Equatable, Sendable { public let text: String; public let tone: PromptStatus.Tone }
public enum StatusBarText {
    public static func line(menu: MenuState, mode: Mode, rows: [PromptRow]) -> StatusLine
}
```

`rows` is the board's visible rows (the overlay passes `board.visibleRows(now:)`). First match wins:

| # | Condition | Text | Tone |
|---|---|---|---|
| 1 | `menu == .microphoneDenied` | `Microphone denied: allow NoHands in System Settings` | bad |
| 2 | `menu == .needsAccessibility` | `Needs Accessibility: allow NoHands in System Settings` | bad |
| 3 | `menu == .error(m)` | `Error: <m> · choose Retry in the menu` | bad |
| 4 | `menu == .loading` | `Loading speech model…` | waiting |
| 5 | `menu == .paused` | `Paused · Resume Listening in the menu` | muted |
| 6 | a non-final row exists | `<prompt> · <status.text>` of the live row, picked `running` > `heard` > `listening` > `held`, newest first within a kind | the row's tone |
| 7 | a final row is still on the board | `<prompt> · <status.text>` of the most recently updated final row | the row's tone |
| 8 | `mode == .sleep` | `Asleep · say wake up` | muted |
| 9 | `mode == .dictation` | `Dictating · say stop dictating` | active |
| 10 | otherwise | `Listening` | good |

- A running task therefore shows its goal and step, e.g. `open YouTube and search for cats · step 2 · type the
  search`. When it ends, its final row (`done · …`, `stopped`, `failed …`) shows for as long as the board keeps
  it (6 s, `finalLinger`), then the bar returns to `Listening`. This is the acceptance's "Stop shows stopped,
  then returns to listening", with no second timer.
- Idle text never times out. The text is not truncated in Core; the view truncates the tail to its width.

## Panel

- A separate `statusPanel` in `OverlayController`, made by the existing `makePanel()` (non-activating,
  `ignoresMouseEvents`, `.screenSaver` level, all Spaces, full-screen auxiliary, can't become key or main).
- `StatusBarView`: a dark rounded capsule like the board (same fill), a tone dot from `BoardView.color(_:)`, and
  one line of 13 pt text truncated at the tail. Height 28 pt; width fits the text, between 160 and 520 pt (and
  never wider than the screen minus 32).
- Placed horizontally centred on the visible frame (menu bar and Dock excluded) of the screen the pointer is on:
  - **Top:** 8 pt below the menu bar. The prompt board then starts below the bar (bar height + 6 pt gap), so the
    two stack and the bar never covers a board row.
  - **Bottom:** 8 pt above the bottom of the visible frame (above the Dock). The board stays where it is today.
  - **Off:** the panel is ordered out; the board stays where it is today.
- While the grid or the number badges are on screen (`state != .none`) the bar is ordered out, and it comes back
  when they are hidden. That keeps it from covering a badge or a grid number.
- Redrawn on every change the overlay already sees (`report`, `showHUD`, the board's scheduled redraw,
  `showGrid`/`showLabels`/`hide`) and when the app state or position changes.

New `OverlayController` API, called from `AppDelegate`:

```swift
public func setAppState(_ menu: MenuState, mode: Mode)   // from refresh()
public var statusBarPosition: StatusBarPosition { get set } // redraws at once
```

## Setting

- `NoHandsCore/StatusBarPosition.swift`: `enum StatusBarPosition: String, CaseIterable, Sendable { case off,
  top, bottom }` and `static func stored(_ raw: String?) -> StatusBarPosition`, which returns `.top` for `nil`
  or an unknown value.
- Stored in `UserDefaults.standard` under `statusBarPosition` as the raw string. Read once at launch; written on
  each menu choice. Not in `config.json` (out of scope, and the app never writes that file).
- Menu: a **Status Bar** item with a submenu `Off`, `Top`, `Bottom`; the current one has a checkmark. Choosing
  one writes the default, sets `overlay.statusBarPosition` (the bar moves or hides at once), and updates the
  checkmarks. It goes in the group with Start at Login and Open config.json:

```
Start at Login
Status Bar        ▸  Off / ✓ Top / Bottom
Open config.json…
```

## Code layout

- `NoHandsCore/StatusBar.swift`: `StatusLine`, `StatusBarText.line(menu:mode:rows:)`, `StatusBarPosition`.
- `NoHandsMac/OverlayController.swift`: `statusPanel`, `StatusBarView`, placement, board offset when the bar is
  at the top, hide while grid or labels show.
- `Sources/NoHands/AppDelegate.swift`: read and write the default, the submenu, `overlay.setAppState` from
  `refresh()`.
- No change to `VoicePipeline`, `TaskRunner` or `PromptBoard`: the task's step already reaches the board through
  `overlay.report`, and the bar reads the same rows.

## Tests

- `StatusBarTextTests` (Core, one table): each row of the table above, including the priority cases that would
  hurt if they broke (a running task beats a held one; a problem state beats a running row; paused beats a
  stopped row; a final row beats idle; idle command mode gives `Listening`, sleep and dictation give their
  lines).
- `StatusBarPosition.stored`: `nil`, `""`, `"middle"` → `.top`; each raw value round-trips. Folded into the
  same test file as a second small table.
- Not tested: panel layout, colours, placement, the menu (UI and framework behaviour, per AGENTS.md).

## Docs

- `README.md`: a **Status bar** paragraph after the Prompt board paragraph (what it shows, Off/Top/Bottom in
  the menu, remembered across launches, hidden while the grid or numbers are up).
- `docs/superpowers/specs/2026-11-04-nohands-design.md`: add the bar to the `OverlayController` line and the
  Status Bar item to the menu group.
- `docs/agents/project.md`: no change (no repo fact changes).

## Manual checks (listed in the PR, not claimed as passed)

1. Delete the default (`defaults delete <bundle id> statusBarPosition`), launch `build/NoHands.app` → the bar is
   at the top centre and says `Listening` when idle; the board's rows appear below it.
2. "open YouTube and search for cats" → the bar shows the goal and the current step, then the finish line, then
   `Listening`. During a task, "stop" → `stopped`, then `Listening`.
3. Pause Listening → `Paused …`; Resume → `Listening`. Revoke Accessibility → `Needs Accessibility: …`.
4. "go to sleep" → `Asleep · say wake up`; "wake up" → `Listening`.
5. Status Bar ▸ Bottom moves it at once; Off hides it at once; quit and relaunch → still off. Top → back.
6. "show numbers" and "grid" → the bar hides while they show and returns after "hide".
7. Clicks pass through the bar to the app beneath it; it never takes focus.
8. Two displays: move the pointer to the other screen; the bar moves there on its next update.

## Leaves out

- Changing what the board shows or how long rows linger.
- Spoken status (NH-60), dragging, themes, per-display placement, a `config.json` key.
- A voice command for the setting (no new phrase; the README voice table is unchanged).

## Calls I made

- **The bar hides while the grid or number badges are up.** The ticket says it must not block them; a bar near
  the top would cover badges on toolbars and tabs, so it steps aside rather than being "always on" during
  targeting.
- **At the top, the bar sits above the board and pushes the board down** (stacked) instead of moving the bar to
  the bottom by default.
- **The bar follows the pointer's screen only when it redraws** (any prompt, notice, state change, and the app's
  5 s permission poll), not continuously, so moving to another display can take up to 5 s to follow.
- **A finished task shows its final row for the board's 6 s linger, then `Listening`**: the bar reuses the board
  rows instead of keeping its own timer.
- **Row text is `<prompt> · <status>` for every row**, including `listening…` while you speak and `held`, so the
  bar mirrors the newest live prompt, preferring the running task over a held one.
- **Problems and pause outrank a running row**: if a permission is lost mid-task, the fix is what the bar shows.
- **Fix wording:** `Microphone denied: allow NoHands in System Settings`, `Needs Accessibility: allow NoHands in
  System Settings`, `Error: <m> · choose Retry in the menu`, `Paused · Resume Listening in the menu`,
  `Asleep · say wake up`, `Dictating · say stop dictating`.
- **The invalid-config notice is not in the bar**; it stays in the menu and its launch notice.
- **Storage is `UserDefaults` key `statusBarPosition`**, an unknown or missing value means Top.
- **Size and placement:** 28 pt tall, 160–520 pt wide, 8 pt from the menu bar or the Dock, 13 pt text, styled
  like the board.
- **Menu placement:** between Start at Login and Open config.json.
