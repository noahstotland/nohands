# NH-155: Apply the quit, close and Apple menu guards to click_in on the menu bar: Design

**Date:** 2026-11-23  **Ticket:** [NH-155](https://github.com/noahstotland/nohands/issues/155)
**Status:** Draft

## Intent

A model step `click_in` with `surface: "menubar"` reaches the same menu items as `menu_item`, but none of the checks `menu_item` gets:

- `ShortcutGuard.blocked` looks at `.pressKey`, `.closeApp` and `.menuItem` only, so `.clickIn(.menubar, "Quit Safari")` passes for any goal.
- The executor (`ActionExecutor+Harness.swift`, `case .clickIn`) never calls `MenuMatch.isAppleMenuTitle`, so "Shut Down", "Restart" and "Force Quit" are reachable.
- `MenuBarGuard.blocked` looks at `.click` only, so `.clickIn(.menubar, "History")` opens a top-level menu the goal never asked for.

`IrreversibleGuard` already handles `.clickIn` (Send, Delete), so those three are the gap.

## Scope

Builds:

- **Quit and close titles.** `ShortcutGuard.blocked` gives `.clickIn(.menubar, name)` the same title rule as `.menuItem(title)`: a name with a quit or close word ("Quit Safari", "Close Window", "File>Close Tab") is blocked unless the goal has the matching allow word, with the NH-150 negation rule ("don't quit Safari" allows nothing). Same message form: `blocked: menu item <name> not allowed for this request`.
- **Apple menu titles.** `ShortcutGuard.blocked` refuses `.clickIn(.menubar, name)` when `MenuMatch.isAppleMenuTitle(name)` (the last part, for a path) or `MenuMatch.isLookalike(name)`, whatever the goal says: `blocked: <name> is an Apple menu item`. "shut down the mac" still refuses "Shut Down", as `menu_item` does today.
- **Top-level menu bar items.** `MenuBarGuard.blocked` refuses `.clickIn(.menubar, name)` when `name` matches a top-level menu bar title (the `menuBarTitles` the observation already carries) that `MenuBarGuard.allows(title:goal:)` does not allow. Same message form as a `.click(.element)` on the bar.
- **Executor backstop.** In `case .clickIn`, for `surface == .menubar`, refuse a found item whose name is an Apple menu title or a lookalike, and, on a model step (`labelSnapshot != nil`), one whose plain name differs from the name the step sent. agent-desktop's `find` falls back to a contains match, so the name the guards checked is not always the item clicked ("Safari" could find "Quit Safari"). The message is `no '<name>' in menubar`, as when nothing is found.

Non-goals: `menuBarExtras`, `dock`, `menu`, `sheet`, `alert` and `popover` surfaces; negation itself (shipped in NH-150); new voice phrases.

Anti-goals: a second copy of the quit/close title rule (the `.clickIn` case shares the `.menuItem` code path inside `ShortcutGuard`).

## Design

### ShortcutGuard (NoHandsCore)

Pull the body of the `.menuItem(let title, _)` case into a private `menuTitleBlocked(_ title: String, words: Set<String>) -> String?` and call it from both cases:

```swift
case .menuItem(let title, _):
    if let why = menuTitleBlocked(title, words: words) { return why }
case .clickIn(.menubar, let name):
    let leaf = MenuMatch.leaf(of: name) ?? name
    if MenuMatch.isAppleMenuTitle(leaf) || MenuMatch.isLookalike(name) { return "blocked: \(name) is an Apple menu item" }
    if let why = menuTitleBlocked(name, words: words) { return why }
```

The Apple check is only on `.clickIn`; `.menuItem` keeps its refusal in the executor, unchanged, so no behavior moves for packs or the grammar. `PackFile` calls `ShortcutGuard.blocked` on pack phrases, but packs have no `click_in` step, so nothing changes there.

### MenuBarGuard (NoHandsCore)

Add a second loop over `.clickIn(.menubar, name)`: `LabelAssigner.find(named: name, in: items(menuBarTitles))`, and refuse when found and not allowed. This runs even while number badges are showing: the badge exception exists because the user picked a number, and a `click_in` names no number.

### Executor (NoHandsMac)

```swift
case .clickIn(let surface, let name):
    ...
    guard let m = await harness.find(...) else { return "no '\(name)' in \(surface.rawValue)" }
    if surface == .menubar, MenuMatch.isAppleMenuTitle(m.name) || MenuMatch.isLookalike(m.name)
        || (labelSnapshot != nil && MenuMatch.plain(m.name) != MenuMatch.plain(MenuMatch.leaf(of: name) ?? name)) {
        return "no '\(name)' in menubar"
    }
```

## Tests

One table-driven test per rule in `NoHandsCoreTests`:

- `ShortcutGuardTests`: `.clickIn(.menubar, …)` rows: "Quit Safari" blocked for "open the latest video" and for "don't quit Safari", allowed for "quit Safari"; "Close Window" blocked unless a close word; "Shut Down", "Force Quit", "Log Out Noah…", "Apple > Restart" refused even for "shut down the mac"; "Save" allowed; `.clickIn(.dock, "Quit")` untouched.
- `MenuBarGuardTests`: `.clickIn(.menubar, "History")` blocked for "open the latest video", allowed for "open the history menu" and with badges showing still blocked; `.clickIn(.menubar, "Save")` (not a top-level title) left alone.

The executor backstop needs agent-desktop and a real menu bar: manual, under Not proven.

## Docs

No voice phrase, config or CLI change. The architecture spec's guard list, if it names which actions each guard covers, gets `click_in` on the menu bar added; the documenter checks.

## Calls I made

- **The Apple-menu refusal for `click_in` lives in `ShortcutGuard`** (core, unit tested), with a backstop on the found name in the executor, rather than only in the executor as `menu_item` has it. That makes the ticket's "Shut Down is refused" acceptance testable.
- **A lookalike `click_in` menubar name is refused as an Apple menu item** (same message), not given its own message: it is a disguise either way, and one message keeps the guard small.
- **A model `click_in` on the menu bar must click the exact title it named** (after `plain`), like model `menu_item` steps since NH-150, so the contains fallback can't turn a guarded name into a different item.
- **MenuBarGuard ignores the badge exception for `click_in`**: there is no number the user chose.
- **Only `.menubar`.** `menuBarExtras` (status items) and `menu` (an open menu) can hold quit items too, but the ticket names the menu bar; a follow-up can extend it if needed.
