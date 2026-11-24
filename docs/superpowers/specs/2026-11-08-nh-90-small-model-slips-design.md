# NH-90: Make the task loop robust to small-model slips — Design

**Date:** 2026-11-08  **Ticket:** [NH-90](https://github.com/noahstotland/nohands/issues/90)
**Status:** Shipped
**Shipped:** in PR #97, as specified

## Intent

On the local model (qwen2.5:7b-instruct) a multi-step task dies on slips the loop does not catch: it types a URL instead of opening it, clicks a menu-bar item because an example clicked "label 4", and repeats a failed step until the repeat detector ends the task. Catch those slips in code and in the screen we send, so the local backend can finish simple tasks.

## Goals and anti-goals

Non-goals: running the YouTube route in code (#91), a bigger model, learned routes (#46).

Anti-goals (a failure even if the fixtures pass):

- Text the user asked to type opens a browser instead.
- A file name or an ordinary word opens a website.
- A spoken "stop" is delayed or lost.
- "Click edit, click copy" stops working, by voice or as a task.
- A typed address opens anything but `http(s)`.

## Where the code differs from the ticket

- Numbers sort by screen position and the menu bar sits at y=0, so the fix goes after numbering, in `ScreenObserver`, not in the walk.
- A click by name resolves to the first match of a fresh walk, which is the menu bar, so a page button titled "Edit" loses.
- `WebAddress.url(for:)` is too loose for typed text: `notes.txt`, `3.14` and `apple` all parse.
- The system prompt teaches the slip ("type a URL"), and click fixtures require a number, so a blanket "prefer names" line would fail them.
- agent-desktop snapshots have no menu bar, so the sort and guard key on the native `AXMenuBarItem` role.

## Design

Chosen: code guards plus a cleaner prompt and screen.

All new logic is pure, in `NoHandsCore`, beside `ShortcutGuard`. Per step in `TaskRunner.run`: `TypedAddressGuard.rewrite` first, so History and repeats see `open_url`; then `ElementNames.bind`, which rewrites only what runs so History keeps the model's own targets; then `ShortcutGuard`, `TabGuard`, `MenuBarGuard`; otherwise execute.

### Typed-address guard

A `type_text` whose whole trimmed text is a web address becomes `open_url`. `WebAddress.typedAddress` requires `url(for:)` to succeed plus an explicit `http(s)://`, a `www.` prefix, or a last label from a short list of web endings (`com`, `org`, `io`, `tv`, ...). File-like endings (`md`, `py`, `zip`, `mov`) and bare site names are out.

- A plain Return straight after a converted action is dropped.
- The guard does nothing when the goal has an exact text-entry word (type, write, enter, paste, dictate, fill, send, reply, post, comment, message, email, text and their forms). "Put" is not one.
- A `type_text` after `open_app` or `command-l` in the step is left alone: that route works today and fixtures accept it. `type_into`, `set_value` and `search` are never rewritten.

### Menu-bar guard

`MenuBarGuard` blocks (whole step runs nothing, recorded as a failure):

- A label click on a menu-bar-role element.
- A by-name click matching `ScreenObservation.menuBarTitles` (all menu-bar titles found before the cap).

It allows the click when the goal has `menu` or `menubar`, or every word of the title is in the goal. It is off while badges show, since the user chose those numbers.

### Binding names to the list

`ElementNames.bind` turns `.click(.element(name))` into `.click(.label(n))` when:

- It is the step's first action (later labels would use stale coordinates).
- `name` exactly equals (case-insensitive) a non-menu-bar title in the list. Exact only, so "File" cannot bind to "Profile" and slip past the guard.
- The name is not a menu-bar item the goal allows.

It runs only in the task loop; spoken "click edit" still goes to the menu bar.

### Repeat nudge

When the last two History records have identical, non-empty actions, the request adds a line saying so and that a third identical step ends the task. It goes to both backends; `RepeatDetector` still ends the third repeat.

### Element list

`LabelAssigner.menuBarLast` renumbers so page elements start at 1 and menu-bar items follow, before the cap, so the cap cuts the menu bar. Only the task-loop observation uses it; the one-shot is unchanged, and nothing is renumbered while badges show.

### Prompt and examples

- The shared task paragraph now says to prefer `open_url` with a direct URL over clicking through menus: no "type", no real handle (Claude's cached prompt changes once).
- A local-only rule, appended after the warm-up prefix: with `Overlay` none, click a titled element by exact `target_name`; use a label for untitled or duplicate titles or when `Overlay` is labels.
- `IntentExamples.turns` keeps count and order, uses a fictional channel, and answers step 2 by element name.

## Tests

One table-driven test per rule, no permissions or Ollama: typed-address guard, menu-bar guard, name binding, repeat nudge, `menuBarLast`, examples, and one `TaskRunner` wiring test. Fixtures are not edited. Manual (PR): both fixture files pass on Claude; local pass rate stays at or above 30 of 40; the Outdoor Boys task on the local model opens by `open_url`.

## Calls I made

- **The URL guard is narrower than the ticket's "anything `url(for:)` parses"**, which would open `notes.txt`. Cost: an address on an unusual ending stays typed, as today.
- **The guard applies in every app, as the ticket says.** Risk: a link typed in Messages may open a browser.
- **Name binding is added (not in the ticket).** Without it "prefer names" would hit a same-titled menu-bar item and the guard would block it. Narrow: exact title, first action.
- **The named-target line is local-only and only with no overlay**, since Claude picks numbers well and fixtures require them.
- **Menu-bar items are sorted last, not dropped**, so "click the file menu" works.

