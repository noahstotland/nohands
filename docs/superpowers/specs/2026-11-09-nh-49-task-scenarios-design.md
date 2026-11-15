# NH-49: Task scenario suite: Design

**Date:** 2026-11-09  **Ticket:** [NH-49](https://github.com/noahstotland/nohands/issues/49)
**Status:** Shipped
**Shipped:** in PR #101, with differences: [as-built](../as-built/2026-11-09-task-scenarios.md)

## Intent

`TaskOutcome.done` is only the model's word. A scripted suite runs goals live, checks the screen independently, and prints pass or fail, steps and time per goal.

## Goals and non-goals

- **Goals:** `scripts/task-scenarios.json`, `nohands-cli scenarios [file] [--only name]`, six scenarios, checks as pure `NoHandsCore` functions, an as-built note with the first run.
- **Non-goals:** CI runs, scoring cost, changing the task loop or intent fixtures.
- **Anti-goals** (each fails the suite): a pass because the model said `done` or an earlier scenario left something behind; a check passing on an empty screen read; `swift test` needing a screen or model; slow Ctrl-C; private titles or URLs in the note.

Chosen: a CLI subcommand reusing `TaskRunner`. Rejected: a shell loop over `task` (fails "pure functions in core").

## Design

### Scenario file

A JSON array of `{name, goal, start, ready, success, maxSteps}`:
- `name` is unique; `--only` matches exactly.
- `maxSteps` is 1 to 30. `start` is exactly one of `{"app": name}` or `{"url": http/https URL}`.
- `ready` (optional) are checks that must hold before the goal starts. `success` is a non-empty list; all must hold.
- A check has one key: `windowTitleContains`, `urlMatches` (case-insensitive regex), `elementVisible`, `elementAbsent`, or `mediaPlaying` (`true`).
- `{run}` in `goal`, `ready` and `success` becomes the suite start time in Unix seconds.

Any invalid scenario, including `elementAbsent` with no `elementVisible` beside it, exits 1 naming it; nothing runs.

### Pure logic in `NoHandsCore`

- Matches ignore case; `urlMatches` needs a URL.
- `elementAbsent` holds only when the element list is not empty and no title matches. An unbuilt page tree still lists the menu bar, so validation requires an `elementVisible` proving the page was read.
- **Default start state.** `app`: frontmost app name contains the name and the window title is not empty. `url`: same host and path, ignoring leading `www.` and trailing `/`, so an earlier `youtube.com/watch` tab is not the `youtube.com/` start. A redirecting start URL is `start-failed`.
- **Verdict:** done with checks holding `pass`; done without `false-done`; stuck, failed or ignored with checks holding `unclaimed`, otherwise `fail`; `stopped`, `start-failed`, `not-run` are not evaluated. `false-done` and `unclaimed` are what the suite exists to expose.

### The command

`file` defaults to `scripts/task-scenarios.json`. Before running: validate, load the backend, check Accessibility, print model, backend and harness, remind the operator to close old tabs, wait 3 s. Each scenario runs once in file order:
1. Activate the app or open the URL.
2. Poll every 1 s for up to 20 s until the start state and `ready` hold; else `start-failed`.
3. Run a `TaskRunner` as `task` builds it, step limits set to `maxSteps`.
4. Unless stopped, poll every 1 s for up to 3 s until all checks hold; print failing checks. Print verdict, steps, time.
5. If `mediaPlaying` was checked and a Pause control is listed, click it; else print `still playing`.

Wait 2 s between scenarios. Exit 0 when all pass, 2 otherwise, 1 for usage or file errors, 130 on a second Ctrl-C. The first Ctrl-C cancels the task, marks it `stopped` and the rest `not-run`, and exits 2.

The checks use a separate `ScreenObserver`: element cap 300 on every backend, and no audio probe, so `media` is `playing` only with a Pause control on screen (a leftover video would otherwise pass a later scenario). A player with no Pause control scores `false-done`.

### First scenarios

- `youtube-latest` (24 steps): "Turn on the latest Outdoor Boys video"; watch URL, media playing, element `Outdoor Boys`.
- `youtube-search-play` (24), `wikipedia-article`, `site-search`, `textedit-save` (12 each).
- `cookie-banner` (12): `ready` is a real site's accept button visible, so a page with no banner is `start-failed`; success is a stable link visible and the accept button absent. A rerun is `start-failed` until cookies are cleared. The as-built names the site.

The README gets a `scenarios` CLI row. The as-built holds a table of names, verdicts, steps and times only.

## Testing

Table-driven tests cover validation, each check, the start state, verdicts and `{run}`. Manual: the live run and Ctrl-C.

## Calls I made

1. **No Anthropic key on this machine**: the backend is local (`qwen2.5:7b-instruct`), noted; the Claude run goes under Not proven.
2. **The first run takes over the screen** for minutes and leaves tabs open.
3. **Ctrl-C ends the whole suite**, so it does not grab the screen back.
4. **`success` is a list, all required**: one check cannot tell that video from some video.
5. **Added `elementAbsent` and `ready`**: absence means nothing unless the banner was there first.
6. **`mediaPlaying` counts a Pause control only**: a false failure is visible, a false pass is not.
7. **Seven verdicts** instead of pass and fail.
8. **"Latest" is not verified**; the check proves an Outdoor Boys video plays.
9. **Nothing is cleaned up** except playback.
10. **No retries**, so a flaky pass looks flaky.
11. **Timeouts** (20 s, 3 s, 2 s) may be adjusted after the first run.
12. **`url` starts accept only http and https.**
13. **`site-search` allows a direct search URL.**
14. **A pre-roll ad counts as playing.**
15. **No completeness signal for screen reads**; `elementVisible` covers it.

## Left to the builder

File split, console format, cookie-banner site.
