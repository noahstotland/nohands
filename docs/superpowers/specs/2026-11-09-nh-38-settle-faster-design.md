# NH-38: Settle faster after each task step — Design

**Date:** 2026-11-09  **Ticket:** [NH-38](https://github.com/noahstotland/nohands/issues/38)
**Status:** Shipped
**Shipped:** in PR #124, with differences: [as-built](../as-built/2026-11-15-nh-38-settle-faster.md)

Written in team mode without a brainstorming session; open choices are under [Calls I made](#calls-i-made).

## Intent

After every step the loop observes until two readings match, for up to `settleMs` (3 s). A scroll waits like a page load, and a ticking value uses all 3 s. Make the wait depend on what the step did, so tasks finish sooner without the model acting on a half-loaded screen.

Anti-goals: a half-loaded page after navigation more often than today; a "stop" waiting on a settle; any settle longer than today (`settleMs` stays the limit); changes to repeat detection, the step cap or the guards.

## What changes

### 1. A policy per step (`NoHandsCore`)

`SettlePolicy.for(actions)` gives each action a level; the step takes the highest. The switch has no `default`, so a new action must choose.

- `none`: one observation, no sleep. `wait`, `look`, `check_media`, `ignore`, reads, `clipboard_set`, an empty list.
- `oneLook`: sleep `minSettleMs` (300 ms, capped at `settleMs`), observe once. Typing (text with a newline is `full`), `set_value`, `clear`, scrolls, `focus`, moves, `check`, `uncheck`, `wait_for`, a key with no modifier other than Return.
- `full`: today's polling. Navigation, `click`, Return, keys with Command, Control or Option, searches, menus, everything else.

`settleMs == 0` means one observation, no sleep. A failed or blocked step keeps its actions' policy.

### 2. A ticking value no longer holds the loop

`SettleWatch` keeps the last three readings and settles when `Settle.same` holds for two, or when the last two differ only in element values and each changed element also changed between the previous two. Elements are identified by role, title and states. Any other change (app, title, URL, surface, media state, element set) keeps polling. Closes the settle item in NH-7.

### 3. A typed wait when a window is still coming (`TaskRunner`)

When the harness is agent-desktop, the step opened a URL or app, and the front app has no window, run `wait --event window-opened --app <front app>`. Timeout is the time left in `settleMs`, at most 1500 ms, through `runCancellable` so "stop" kills it.

- `open_app`, event seen: one observation.
- `open_url`, event seen: keep polling, because the window appears before its page loads.
- Timeout or failure: keep polling. A failed wait never fails the step.

### 4. `settle=<ms>` in the log

`TaskRunner.settleTimes` holds each step's value. `runTask` appends it: `task(done, steps=3, settle=120+300+90)`.

## Approaches

The ticket waits on `window_opened` for every URL or app step. But the event is a baseline diff taken when the wait starts, so an existing window never fires it, and `open_url` in a running browser opens a tab. So the wait runs only with no window (chosen); waiting on every step would burn the timeout on each `open_url`.

## Testing

Table-driven: policy and watch rules, per-policy sleeps, a stop during the harness wait, the window wait with a fake harness. Real-task timings need Accessibility and a model, so the PR lists them as not proven.

## Docs

`README.md`'s task loop and `settleMs` say the wait depends on the step and `settleMs` is the most it takes.

## Calls I made

- **"Ticking" covers element values only.** A ticking title still takes the full `settleMs`, since titles may still be filling in.
- **A key with no modifier, other than Return, is `oneLook`.** Command, Control and Option keys are `full` because they can switch tabs or reload.
- **Unnamed actions default to `full`**, except `scroll_to`, `focus`, `wait_for` (`oneLook`) and no-change actions (`none`).
- **NH-7 is not edited here.**

Risk: suggestions slower than 300 ms are missed after `type_text`. The model sees them one step later.
