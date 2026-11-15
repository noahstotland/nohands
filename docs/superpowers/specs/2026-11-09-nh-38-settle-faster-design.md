# NH-38: Settle faster after each task step — Design

**Date:** 2026-11-09  **Ticket:** [NH-38](https://github.com/noahstotland/nohands/issues/38)
**Status:** Shipped
**Shipped:** in PR #124, as specified

Written in team mode without a brainstorming session. Every choice the ticket left open is under
[Calls I made](#calls-i-made).

## Intent

A multi-step task spends much of its time waiting. After every step the loop observes the screen until two readings
match, for up to `settleMs` (3 s), and one native reading can take a second on a busy page. A scroll waits like a page
load, and a page with a ticking value uses the whole 3 s every time. Make the wait depend on what the step did, so
tasks finish sooner without the model acting on a half-loaded screen.

## Goals and non-goals

Goals are the ticket's Scope and Acceptance. Non-goals are its Out of scope: the cost of an AX walk (NH-17) and the
model's own `wait` actions.

Anti-goals, which would make this a failure even if the tests pass:

- The model sees a half-loaded page after a navigation more often than it does today.
- A spoken "stop" has to wait for a settle or a harness wait to run out.
- A settle takes longer than today on any path. Today's limit is `settleMs` in wall time, and that stays the limit.
- Repeat detection, the step cap or the guards change.

## How it works today

`TaskRunner.settle` observes, sleeps 250 ms, observes again, and stops when `Settle.same` says two readings match
after at least 300 ms, or when `settleMs` is used up. The same policy runs for every action. `settle` is called in
three places: after a step, for the playback check after a `done`, and before step 1 when a Chromium page tree was just
exposed. That last call has no step and keeps today's behaviour.

## What changes

### 1. A policy per step (`NoHandsCore`, tested)

`SettlePolicy.for(_ actions: [Action])` returns one of three policies. Each action has a level and the step gets the
highest level among its actions, so `[open_url, wait]` is `full` and `[type_text, wait]` is `oneLook`. The switch is
exhaustive with no `default`, so a new action kind must choose a level.

| Policy | What the loop does | Actions |
|---|---|---|
| `none` | One observation with no sleep | `wait`, `look`, `check_media`, `ignore`, the reads (`read_clipboard`, `read_value`, `read_notifications`), `clipboard_set`, and an empty list |
| `oneLook` | Sleep `minSettleMs` (300 ms, capped at `settleMs`), then one observation, no polling | `type_text`, `type_into`, `set_value`, `clear`, `scroll`, `scroll_element`, `scroll_to`, `focus`, `move_cursor`, `move_window`, `check`, `uncheck`, `wait_for`, a key with no modifier other than Return |
| `full` | Today's polling, up to `settleMs` | `open_url`, `open_app`, `click`, Return, a key with Command, Control or Option, `search`, `search_site`, `menu_item`, `click_in`, `window`, and everything else (`select_option`, `expand`, `drag`, tab and window closes, mouse press and release, overlays, mode changes) |

`settleMs == 0` still means one observation with no sleep, for every policy. A step that failed or was blocked uses
the policy of its actions.

### 2. A ticking value no longer holds the loop (`NoHandsCore`, tested)

`SettleWatch` replaces the direct `Settle.same` call in the polling loop. It keeps the last two readings and is fed one
at a time. It reports settled when either:

- `Settle.same` holds for the last two readings, or
- the last two readings differ only in element values, and every element that changed also changed value between the
  two readings before them.

An element is identified by role, title and states, because numbers and refs are reassigned on each snapshot. Elements
sharing that identity are compared as a group of values. Any change to the app, window title, URL, surface, media
state, or the set of elements counts as real and keeps polling. The `minSettleMs` floor and the `settleMs` limit still
apply. This closes the settle item in NH-7.

### 3. A typed wait when a window is still coming (`TaskRunner`)

Applies when the task's harness is agent-desktop, the step opened a URL or an app, and the front app has no window yet.
The runner runs `wait --event window-opened --app <front app>` with the time left in `settleMs` as the timeout. That
time counts toward the limit, and the wait goes through `runCancellable` so a spoken "stop" kills it.

- `open_app` with the event seen: one observation.
- `open_url` with the event seen: polling continues for the time left, because the window appears before its page loads.
- Timeout or failure: polling continues for the time left. A failed wait never fails the step.

If the front app already has a window, there is no wait and the step polls as `full`.

### 4. `settle=<ms>` in the utterance log

`TaskRunner` gets `public private(set) var settleTimes: [Int]`, reset at the start of each run, holding the value each
`onStep` reports. `runTask` appends it to both log strings: `task(done, steps=3, settle=120+300+90)`. Numbers are not
private, so it can go in the public `outcome` field.

## Approaches

**For the agent-desktop wait, this is the part that differs from the ticket.** The ticket asks to wait on
`window_opened` or the window title whenever a step opened a URL or an app. Two facts from `agent-desktop` 1.1.0 and
the code work against that:

- `--help` says `--event` is "detected by baseline diff", and the baseline is taken when the wait starts. The executor
  has already opened the URL and, for `open_app`, waited for the app to come to the front, so a window that exists by
  then is in the baseline and the event never fires.
- `open_url` in a running browser opens a tab, so no window opens. `wait --window` needs the title up front, and a page
  title can't be known before it loads.

1. **Wait only when no window exists yet, then keep polling for URLs (chosen).** The wait can only fire in a state
   where it means something. The common path, a tab in a running browser, costs nothing extra.
2. **Wait on every URL or app step, as the ticket says.** In the common path the event never fires, so each `open_url`
   burns its whole timeout. That is slower than today.
3. **Start the event wait before running the action, so the baseline is correct.** Correct for new windows but still
   never fires for a tab, and it needs a concurrent subprocess racing the action inside the executor.
4. **Take one snapshot straight after the event for URLs too, as the ticket says.** The window arrives before the page,
   so the model would read an empty page. That is the first anti-goal.

The ticket's main gain for page loads then comes from the ticking fix and from the local steps no longer polling.

## Testing

Table-driven, per `AGENTS.md`:

- `TaskGuardsTests`: `SettlePolicy` rows, including mixed steps and each `press_key` case. `SettleWatch` rows: a ticking
  value settles on the second poll, a value change together with a new element does not, a changed title or URL does
  not, and a value that changes only once does not count as ticking.
- `TaskRunnerTests` (the ticket's three): a typing step does one sleep and one observation, a navigation step polls until
  readings match, and a ticking value stops by the second poll. Also a `wait`-only step does no sleep, and a stop during
  the harness wait ends the task as `.stopped`.
- With a fake harness: the wait runs only with no window and is skipped otherwise; `open_app` then observes once;
  `open_url` keeps polling; a timed-out wait still gives an observation within `settleMs`.

Existing tests `settleWaitsForTwoEqualObservations` and `settleStopsAtMax` call `settle` with no step and must keep
passing unchanged.

Manual, needs Accessibility and a model: the before and after settle totals on a real 3-step YouTube task with
`nohands-cli task`, in the as-built note. If it can't be run from this environment, the PR lists it under Not proven.

## Docs

`README.md`'s task-loop paragraph and the `settleMs` key say the loop waits up to `settleMs`. Both get one clause saying
the wait depends on what the step did and `settleMs` is the most it can take. The default stays 3000.

## Calls I made

- **The agent-desktop wait is narrower than the ticket.** It runs only when the front app has no window yet, and URL
  steps keep polling after it. See Approaches. An `open_url` in a browser that is already open gets no typed wait.
- **"Ticking" covers element values only, as the ticket says.** Native readings carry no values, so this helps
  agent-desktop readings. On the native path a ticking text that lands in an element's title still takes the full
  `settleMs` after a navigation step. Treating a title as ticking would risk stopping while a page's titles are still
  filling in.
- **A key press with no modifier, other than Return, is `oneLook`.** The ticket only names Return. Keys with Command,
  Control or Option are `full`, because they can switch tabs, reload or go back.
- **Actions the ticket doesn't name default to `full`**, which is today's behaviour, except `scroll_to` and `focus`
  (`oneLook`, like `scroll`), `wait_for` (`oneLook`, it already blocked on its own signal), and the reads, `look`,
  `check_media`, `ignore`, `clipboard_set` and an empty step (`none`, they change nothing on screen).
- **A failed or blocked step keeps its actions' policy**, rather than a shorter one. Today's wait is the upper bound
  and a partly run step may have changed the screen.
- **`oneLook` skips the immediate first observation.** It sleeps first and observes once, so a typing step costs one
  walk instead of at least two.
- **The per-step log is a `+`-joined list in the existing task log line**, not a new line per step.
- **NH-7 is not edited by this ticket.** The PR says it closes that settle item, and the Chief of Staff or the owner of
  NH-7 can update it.

## Risks

Search-box suggestions that take longer than 300 ms won't be in the reading after a `type_text`. The next step can
still press Return, and if the model wants a suggestion it sees the list one step later. A native reading after a
local edit is taken once, so a slow animation can be caught mid-way. Neither ends a task, and both cost at most a step.
