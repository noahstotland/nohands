# NH-185: Chrome task wastes steps dismissing a phantom Apple menu: Design

**Date:** 2026-11-24  **Ticket:** [NH-185](https://github.com/noahstotland/nohands/issues/185)
**Status:** Proposed

## Intent

In the NH-4 live run, three of eight steps of a Chrome task were a lone Escape press "to close the open Apple menu". No menu was open.

### What causes it

agent-desktop 1.1.0 reports the closed Apple menu as an open `menu` surface, in every app, all the time. Checked on this Mac with no menu open:

```
$ agent-desktop list-surfaces --app "Google Chrome"
{"ok":true,"command":"list-surfaces","data":{"pid":58034,"surfaces":[{"id":"app/children/2/items/0/children/0","item_count":21,"type":"menu"}]}}
```

Finder and Terminal give the same 21-item surface (`items/0` is the first menu bar item, the Apple menu). `agent-desktop snapshot --surface menu` on it returns "About This Mac", "System Information", "System Settings…", "App Store…" and so on, and **every item has the `offscreen` state** and no bounds.

The task loop reads `data.surfaces` from each action's result (`AgentDesktopHarness.act`, `DesktopEnvelope.surfaces`). After a `click`, the next observation in `ScreenObserver.observe` sees `menu`, snapshots `--surface menu` instead of the window, and sends the model a `Surface: menu` line with the Apple menu's items in place of the page. The prompt says a `Surface:` line means a menu is open and to act on it, so the model presses Escape. Escape leaves nothing open, the next step's elements come from the window again, and the model goes on. That matches the log: each lone Escape came right after a numbered `click`.

## Scope

Builds:

- **A closed-surface rule in core.** `DesktopSnapshot.isClosedSurface` (or a static function on a snapshot): true when the snapshot has at least one element and every listable element (`DesktopSnapshot.listable`) carries the `offscreen` state. An open menu, sheet, alert or popover is on screen, so its items are not all offscreen.
- **The observer drops a closed surface.** In `ScreenObserver.observe` (agent-desktop path), when a surface was asked for and its snapshot is closed by that rule, snapshot the window again with no surface and use that. `observation.surface` stays nil, so no `Surface:` line reaches the model. A failed second snapshot falls back to the native walk, as a failed first one does today.
- **The same rule for the plan runner and `find`.** Any other place that passes the reported surface to a snapshot or a `find` (check `TaskRunner`'s plan steps and `ActionExecutor+Harness`) goes through the same check, so a closed Apple menu is never a target.

Leaves out:

- A fix in agent-desktop itself (an upstream tool; it would need an issue there). NoHands works around it on any version.
- A per-step observation digest in `nohands-cli task` (the ticket's first to-do). The cause was found with `agent-desktop list-surfaces` and `snapshot` directly, so it is not needed to fix this bug.
- Changes to the NH-154 and NH-155 guards; they stay as they are.
- Prompt changes: the `Surface:` rule in `IntentSchema.swift` is right when a surface is really open.

Anti-goals: matching the Apple menu by its item names or by the `items/0` id path. The offscreen check is generic and holds for any closed surface agent-desktop reports.

## Design

### Core (`NoHandsCore/DesktopSnapshot.swift`)

```swift
/// A surface snapshot of a menu that is not open: agent-desktop lists the closed Apple menu as a `menu` surface,
/// with every item offscreen.
public var isClosedSurface: Bool {
    let listed = elements.filter(Self.listable)
    return !listed.isEmpty && listed.allSatisfy { $0.states.contains("offscreen") }
}
```

An empty snapshot is not called closed by this rule (nothing to judge); the observer's existing handling of an empty list stays.

### Observer (`NoHandsMac/ScreenObserver.swift`)

```swift
var surface = ...first
var snap = await harness.snapshot(app: app, surface: surface, timeoutMs: snapshotTimeoutMs)
if surface != nil, let s = snap, s.isClosedSurface {
    surface = nil
    snap = await harness.snapshot(app: app, surface: nil, timeoutMs: snapshotTimeoutMs)
}
```

The extra snapshot runs only when agent-desktop reported a surface and it came back closed: one more snapshot after such a step, in place of a whole wasted model step and Escape press (about 3 s each in the run).

## Tests

One table-driven test in `DesktopSnapshotTests` for the rule: an all-offscreen menu (the Apple menu items from the capture above, trimmed) is closed; the same items with one on screen is not; a mix where only unlisted (unnamed, no value) nodes are on screen is still closed; an empty snapshot is not closed.

The observer's re-snapshot needs agent-desktop and a real app: manual, under Not proven, checked by rerunning `nohands-cli task "open the Veritasium channel's newest video"` in Chrome and seeing no lone Escape steps.

## Docs

No voice phrase, config or CLI change. The architecture spec gets a line under the agent-desktop harness if it describes how surfaces are read; the documenter checks.

## Calls I made

- **Judge a surface by its items being offscreen, not by its name or id.** The capture shows every Apple menu item offscreen with no bounds; a really open menu is drawn on screen. This also covers any other closed surface agent-desktop might report.
- **Work around it in NoHands, not wait on agent-desktop.** The installed 1.1.0 has the quirk, and users may keep that version.
- **Re-snapshot the window rather than drop the step's observation.** The model still gets a fresh page view after a click.
- **No step-log digest in the CLI.** The ticket asked for it to find the cause; the cause is found, so it stays out of this PR to keep it to one fix.
- **Not proven that a click's own result carries the phantom surface.** Clicking in the user's Chrome to check was skipped; `list-surfaces` shows the phantom always, and the step log's pattern (Escape after every click) fits. The live rerun in the build checks it.
