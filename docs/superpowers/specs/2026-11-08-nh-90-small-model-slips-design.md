# NH-90: Make the task loop robust to small-model slips — Design

**Date:** 2026-11-08  **Ticket:** [NH-90](https://github.com/noahstotland/nohands/issues/90)
**Status:** Shipped
**Shipped:** in PR #97, as specified

## Intent

On the local model (qwen2.5:7b-instruct) a multi-step task dies on slips a 7B model makes and the loop doesn't catch. It
types a URL instead of opening it, clicks a menu-bar item because an example clicked "label 4", and repeats the failed
step until the repeat detector ends the task. The one-shot fixtures pass at 75%, so the model understands requests. It
can't plan or pick numbers.

Catch those slips in code and in the screen we send, so the local backend can finish simple tasks and click the right
element in any app.

## Goals and non-goals

Goals are the ticket's Scope and Acceptance. Non-goals are its Out of scope: running the YouTube route in code (#91), a
bigger or different local model, learned routes (#46) and the scenario suite (#49).

Anti-goals, which would make this a failure even if the fixtures pass:

- Text the user asked to type opens a browser instead.
- A file name or an ordinary word opens a website.
- A spoken "stop" is delayed or lost. The guards are synchronous and pure, and the existing cancel checks stay where
  they are.
- "Click edit, click copy" stops working, by voice or as a task.
- Model output reaches the executor without going through a guard, or a typed address opens anything but `http(s)`.

## What the code does today, where it differs from the ticket

1. **Menu-bar order isn't caused by the walk.** The ticket points at `AXQuery` walking the menu bar first, but
   `LabelAssigner.assign` sorts by screen position, top to bottom. The menu bar sits at y=0, so it takes the first
   numbers whatever order the walk used. The fix belongs after numbering, in `ScreenObserver`. `AXQuery` doesn't change.
2. **A click by name goes to the menu bar first.** `.element(name)` resolves against a fresh walk, and `LabelAssigner.find`
   returns the first match in walk order, which is the menu bar. If the model names "Edit" or "History" on a page that
   has its own button with that title, the click lands on the menu bar. The ticket's "let the model name a target" can't
   work until this is fixed.
3. **`WebAddress.url(for:)` is too loose to run on typed text.** It accepts known site names (`apple`, `x`, `weather`)
   and any dotted token (`notes.txt`, `main.swift`, `e.g.`, `3.14`). Used as the ticket words it, typing any of those
   would open a website.
4. **The system prompt teaches the slip.** Its task paragraph says "type a URL (e.g. youtube.com/@veritasium/videos)".
   That is both the instruction to type and the real handle the examples are being rewritten to avoid.
5. **Claude and local share the prompt, and the fixtures require numbers.** Every fixture that clicks an element has
   `overlay: labels` and expects `target_kind: label`. A blanket "prefer names" line would fail them.
6. **agent-desktop window snapshots contain no menu bar.** The menu bar is a separate surface whose top-level items have
   role `menuitem`, the same as their children. The sort and the guard therefore key on the native `AXMenuBarItem` role.

## Approaches

1. **Guards in code plus a cleaner prompt and screen (chosen, it is the ticket).** Slips the model can't be talked out of
   are caught deterministically. Each piece is small and testable without a model.
2. **Prompt and examples only.** Cheapest, but the live run shows a 7B copying what it sees whatever the rules say. It
   would leave no safety net when the examples drift.
3. **A local planner or fixed routes.** Would remove the slips rather than catch them, but that is #91 and #46.

## Design

All new logic goes in `NoHandsCore` with no AppKit or network dependency, next to `ShortcutGuard`. `TaskRunner` calls it.

### Order of work on one step (`TaskRunner.run`)

```
step = resolve(...)
step.actions = TypedAddressGuard.rewrite(step.actions, goal)   // onStep, History and repeats all see open_url
repeats.record(step.actions)                                   // unchanged place
actions = ElementNames.bind(step.actions, labels, observation.menuBarTitles, goal)   // only what runs; list-dependent, so not in History
failure = ShortcutGuard ?? TabGuard ?? MenuBarGuard(actions, labels, observation.menuBarTitles, goal, badgesShowing)
          else execute(actions)
```

The navigation check (`markTaskTab`) reads the rewritten list, so a converted URL marks the task's tab. History keeps the
model's targets, so `RepeatDetector` and the nudge compare what the model said and aren't confused when renumbering
changes a bound label.

### Typed-address guard

`TypedAddressGuard.rewrite(_ actions: [Action], goal: String) -> [Action]`:

- A `type_text` becomes `.openURL(url, app: nil)` when its whole trimmed text is a web address.
- A web address is a new, stricter `WebAddress.typedAddress(_:)`: `url(for:)` must succeed, and the text has an explicit
  `http(s)://`, or starts with `www.`, or the host's last label is in a short list of common web endings (`com`, `org`,
  `net`, `edu`, `gov`, `io`, `co`, `tv`, `ai`, `dev`, `me`, `info`, `gg`, `uk`, `de`, `fr`, `ca`, `au`, `jp`, `us`). File
  extensions that are also real endings (`app`, `md`, `py`, `sh`, `zip`, `mov`, `rs`) are deliberately left out. Known
  site names without a dot don't count.
- A `press_key return` with no modifiers, immediately after a converted action, is dropped. A `wait` or anything else in
  between keeps it.
- The guard does nothing when the goal has an exact word showing the user wants text entered: `type`, `types`, `typing`,
  `typed`, `write`, `writes`, `writing`, `enter`, `entering`, `paste`, `pasting`, `dictate`, `insert`, `fill`, `send`,
  `sending`, `reply`, `post`, `comment`, `message`, `email`, `text`. Words are matched with `CommandGrammar.normalize`,
  as `ShortcutGuard` does. "Put" is not on the list: the live goal was "put on the latest…".
- A `type_text` preceded in the same step by an `open_app` or a `command-l` is left alone. The model is typing into a place
  it just set up, and that route works today: `scripts/intent-eval.json` accepts `open_app Chrome, command-l, type_text
  youtube.com, return` for "open youtube on chrome". Converting it would open the page in the default browser or a new tab
  instead.
- `type_into`, `set_value` and `search` are never rewritten. They name a field or carry search words.

Because the result is an ordinary `open_url` built from `WebAddress`, it can only ever be `http(s)`, and `ShortcutGuard`
and `TabGuard` still run on it.

### Menu-bar guard

`MenuBarGuard.blocked(_ actions:, labels:, menuBarTitles:, goal:) -> String?`, in the same shape as `ShortcutGuard`:

- A `.click(.label(n))` whose `labels[n]` has the menu-bar role is blocked with
  `label 4 is the "Edit" menu bar item, not a page element`.
- A `.click(.element(name))` still by name after binding, whose name finds a title in `menuBarTitles` by
  `LabelAssigner.find`, is blocked with `"Edit" is a menu bar item, not a page element`.
- Allowed when the goal has `menu`, `menus` or `menubar`, or when every word of the item's title is in the goal
  ("click edit, click copy").
- Off while number badges are showing (`observation.overlay` is `labels`). The user asked for those numbers and may have
  picked a menu-bar item on purpose.

The element list's cap can cut menu-bar items off, so `ScreenObservation` gets `menuBarTitles: [String]`, every menu-bar
title found before the cap. It isn't rendered in the prompt and `Settle.same` ignores it.

A blocked step runs nothing and goes into History as a failure, like the other guards.

### Binding names to the list

`ElementNames.bind(_ actions:, labels:, menuBarTitles:, goal:) -> [Action]` rewrites a `.click(.element(name))` to
`.click(.label(n))` when all of these hold:

- The click is the step's **first action**. A label resolves against the snapshot taken before the step, so a later click
  in a batch would use stale coordinates. Later named clicks keep today's fresh walk.
- `name` equals the title of a **non-menu-bar** element in the list, trimmed and case-insensitive, lowest number first.
  Exact only, not `LabelAssigner.find`'s prefix and contains tiers, so "File" can't bind to "Profile" and slip past the guard.
- The name isn't a menu-bar item the goal allows. "Click edit, click copy" on a page with its own Edit button stays on the
  menu bar, by the same allow rule as the guard.

Otherwise it is left alone. The model copied the name from that list, so resolving against it is what it meant. It also
makes a named click semantic under agent-desktop, because a label carries a ref. This runs only in the task loop, so spoken
"click edit" goes to the menu bar as it does today.

### Repeat nudge

In `ClaudeRequestBuilder.userBlocks`, when the last two history records have identical, non-empty actions, one more block
follows the history:

```
  Steps 3 and 4 ran the same actions. Try a different approach now; a third identical step ends the task.
```

It is a pure function of `history`, so it is true at exactly a repeat streak of 2 and needs no new state. It goes to both
backends. The third identical step still ends `stuck` through `RepeatDetector`, unchanged.

### Element list

A pure `LabelAssigner.menuBarLast(_ labels: [Int: UIElementInfo]) -> [Int: UIElementInfo]` renumbers so non-menu-bar
elements keep their order from 1 and menu-bar items follow. It runs inside `ScreenObserver.observeNative`, after
`LabelAssigner.assign` and before the untitled filter and the cap, so the cap falls on the menu bar. A `menuBarLast` flag on
`observeNative` is set only by the task-loop `observe`.

- The one-shot `observe` doesn't set the flag and is unchanged.
- While number badges are showing (`overlay` is `.labels`) nothing is renumbered, because the numbers are the ones the
  user can see.
- Items are not dropped when the goal has no menu word. See Calls I made.

### Prompt and examples

- The system prompt's task paragraph (shared) becomes "Prefer deterministic routes: open_url with a direct URL (e.g.
  youtube.com/@mapleridgeworkshop/videos) over clicking through menus". It no longer says "type" and no longer uses a real
  handle.
- A new `IntentSchema.localNamedTargetRule` is appended only to the Ollama system prompt, in `OllamaRequestBuilder.messages`,
  so the warm-up prefix still matches. It says: when `Overlay` is none, click a titled element with `target_kind` "element"
  and `target_name` copied exactly from the list. Use `target_kind` "label" and its number for an element with no title,
  when two elements share a title, or when `Overlay` is labels. Claude's rule 3 stays as it is. The one-shot fixtures that
  click are all `overlay: labels`, so this can't fail them.
- `IntentExamples.turns` keeps the same count and order, with the Xcode "go to netflix" example last.
  - The two-step task uses a fictional channel (`@mapleridgeworkshop`, a video titled for that channel) and intent
    sentences that name it.
  - Its step 2 answers with `target_kind` "element" and the example's video title, which no real screen will have.
  - The Back example, which is `overlay: labels` and so keeps a number, uses a list of 6/11/17.
  - The harness search example's `set_value` target moves to number 4, and its click on the titled "Search" button becomes
    `target_kind` "element", so the example doesn't contradict the local rule.

### Rebasing over open PRs

The build rebases on `origin/main` when it starts and again before the PR. Whichever of these lands first, the later one
rebases. Nothing here depends on their merge order.

- **#19 (NH-3):** its `TaskRunner` and `AXQuery` changes are already on `main` (`onStatus`, `finalStatus`,
  `searchFieldFrame`). If it merges or is closed, there is nothing to reconcile.
- **#20 (NH-17):** changes `AXQuery` and adds `WalkPolicy`. NH-90 doesn't edit `AXQuery`, so there's no textual conflict.
  Its page-first walk still composes: numbers come from screen position and the menu-bar sort runs after numbering. If it
  touches `Fakes.swift`, the additions merge side by side.
- **#86 (NH-41):** the real conflict, in `TaskRunner.run`.
  - It wraps resolve in `while true` and makes `step` a `var`. The typed-address rewrite goes after that loop.
  - It introduces `var actions = step.actions`. `ElementNames.bind` applies to that value before its point mapping, which
    doesn't touch labels.
  - `MenuBarGuard` is appended to its guard chain, on `actions`.
  - Its `ScreenObserver` and `IntentSchema` additions are at other lines. It adds `StepRequest.vision` beside this ticket's
    `ScreenObservation.menuBarTitles`, in different structs.
  - The new failure strings don't start with "no element" or "element changed", so they don't trigger its picture.

## Tests

One table-driven test per rule, in `NoHandsCoreTests`, all runnable with no permissions and no Ollama:

- Typed-address guard: bare domain, `https` URL with a path, `www.` address, ordinary text, `notes.txt`, `apple`, a goal
  with "type", a step that starts with `open_app` or `command-l`, Return dropped only when it directly follows a converted
  URL.
- Menu-bar guard: blocked by label and by name; allowed with "menu", with the title's words, and while badges show.
- Name binding: page element wins over a same-titled menu-bar item; "File" doesn't bind to "Profile"; a later click in the
  step isn't bound; a menu-bar title the goal allows isn't bound; no match is left alone.
- Repeat nudge: present after two identical steps, absent for different or empty ones.
- `menuBarLast`: menu-bar items number last, others keep their order.
- Examples: no real channel handle, no copy of the live goal's URL, clicked label numbers all differ, Xcode last. The
  existing assertion on the `@veritasium` URL in `IntentStepTests` moves to the new handle. This is a unit test and not an
  intent fixture.

One `TaskRunner` test with the existing fakes checks the wiring: a typed URL reaches the executor as `open_url`, History
records it, and a blocked menu-bar click runs nothing.

The fixture files in `scripts/intent-eval*.json` are not edited.

## Manual checks, recorded in the PR

- Both fixture files pass on Claude.
- The local pass rate on `scripts/intent-eval.json` before and after the example rewrite, not below today's 30 of 40.
- The Outdoor Boys task on the local model with Chrome frontmost: step 1 is `open_url`, no step clicks a menu-bar item, and
  the PR shows the step trail to `done` or names the step where it fails and why.

## Calls I made

- **The URL guard is narrower than the ticket's wording.** The ticket says any `type_text` that parses with
  `WebAddress.url(for:)`. That would turn `notes.txt` or the word `apple` into a website, so typed addresses need a scheme,
  `www.` or a common web ending, a goal asking for text entry switches the guard off, and so does a step that opened an app
  or pressed `command-l` first. The cost is that an address on an unusual ending stays typed, which is today's behavior.
- **The guard applies in every app, not just browsers,** as the ticket says. The risk is a request like "tell Sam about
  github.com/foo" in Messages, where the goal has no text-entry word: if the model types only the link, a browser tab opens
  instead. Restricting it to a browser in front would avoid that but miss URLs typed from another app.
- **I added name binding, which the ticket doesn't list.** Without it, "prefer names" sends the click to a same-titled
  menu-bar item, and the menu-bar guard would then block a click that was meant for the page. It is deliberately narrow:
  exact title, first action of the step only.
- **The menu-bar guard is off while number badges are showing.** The ticket doesn't mention badges, but there the user chose
  the number.
- **The named-target prompt line is local-only and applies only when no overlay is showing.** Claude already picks numbers
  well, and the fixtures require them under `overlay: labels`.
- **The shared system prompt changes by one sentence** (no "type", no real handle), so Claude's cached prompt changes once.
  The ticket only named the examples, but leaving this line would keep teaching the slip.
- **Menu-bar items are sorted last, not dropped.** On a busy page the cap removes them anyway. On a sparse window they stay
  at the end, and the guard still blocks a stray click. Dropping them would hide what "click the file menu" needs.
- **Numbers are reassigned after sorting** rather than keeping numbers and only moving lines, so page content starts at 1.
  With badges showing, nothing changes.
- **A typed URL opens in the default browser,** as the ticket says, even if another browser is frontmost. That matches what
  the model's own `open_url` does without `app_name`.
- **The nudge goes to both backends.** It is one line that only appears on a repeat, and one prompt path is simpler.

## Left to the builder

- File and type names for the guards, as long as they stay in `NoHandsCore`.
- Exact wording of the local rule and the rewritten example sentences, within the constraints above and measured against
  the 30 of 40 floor.
- Under agent-desktop, a named click that doesn't bind falls through to the native walk as it does today. `menuBarTitles`
  is empty there because window snapshots hold no menu bar. This is left as is.
