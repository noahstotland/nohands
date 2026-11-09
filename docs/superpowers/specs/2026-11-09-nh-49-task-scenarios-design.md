# NH-49: Task scenario suite: Design

**Date:** 2026-11-09  **Ticket:** [NH-49](https://github.com/noahstotland/nohands/issues/49)
**Status:** Shipped
**Shipped:** in PR #101, with differences: [as-built](../as-built/2026-11-09-task-scenarios.md)

## Intent

Whether NoHands can finish "turn on the latest Outdoor Boys video" is known only by trying it, and the tries (#4, #5)
were written up by hand once. The intent fixtures score one step at a time, and `TaskOutcome.done` is only the model's
word. A scripted suite makes the capability something measured: run the holy-grail goals live, check the screen
independently of what the model claims, and print pass or fail, steps and wall time per goal.

## Goals, non-goals, anti-goals

**Goals.** The ticket's Scope and Acceptance: `scripts/task-scenarios.json`, `nohands-cli scenarios [file] [--only name]`,
the six first scenarios, success checks as pure functions in `NoHandsCore` with a table test, and an as-built note with
the first run.

**Non-goals.** CI runs (the ticket's Out of scope). Scoring cost or tokens. Comparing backends in one command (run it
once per backend). Changing the task loop, its prompt, or the intent fixtures.

**Anti-goals.** Any of these makes the suite a failure even if it prints a clean table:

- A scenario passes because the model said `done`, or because of something an earlier scenario in the same run left
  behind. (A tab left by an earlier *run* is the operator's to close: see Calls I made.)
- A check passes on an empty or failed screen read.
- `swift test` needs a screen, a permission or a model.
- Ctrl-C does not get the screen back promptly.
- The committed note contains private window titles or URLs.

## Approaches

1. **A CLI subcommand that reuses `TaskRunner`, with checks in core (chosen).** The same runner, observer, guards and
   harness choice as `task`, so it measures what the app does. Only the checks and the report are new.
2. **A shell script looping over `nohands-cli task`.** No new Swift for running, but the checks need a fresh observation
   inside the process, and the script would parse human output. It also fails the ticket's "pure functions in core".
3. **Extend `eval` with multi-step cases.** `eval` runs a resolver against a canned context and executes nothing; a
   scenario needs a real screen. They share nothing but the word "score".

## Design

### The scenario file

`scripts/task-scenarios.json` is a JSON array of:

```json
{
  "name": "youtube-latest",
  "goal": "Turn on the latest Outdoor Boys video",
  "start": { "url": "https://example.com/" },
  "ready": [],
  "success": [
    { "urlMatches": "youtube\\.com/watch" },
    { "mediaPlaying": true },
    { "elementVisible": "Outdoor Boys" }
  ],
  "maxSteps": 24
}
```

- `name`: unique in the file; what `--only` matches, exactly.
- `goal`: the text given to the task loop.
- `start`: exactly one of `{"app": "<name>"}` or `{"url": "<http or https URL>"}`.
- `ready`: optional list of checks that must hold before the goal starts, in addition to the default start state below.
- `success`: a non-empty list of checks; all must hold.
- `maxSteps`: 1 to 30, the same range `AppConfig` clamps to.
- A check is an object with exactly one key: `windowTitleContains`, `urlMatches` (a regular expression, case-insensitive),
  `elementVisible`, `elementAbsent` or `mediaPlaying` (must be `true`).
- The token `{run}` in `goal`, `ready` and `success` is replaced by the suite's start time in Unix seconds, so a file
  saved by one run does not collide with the last run's.

Loading fails with exit 1 and a message naming the scenario on: malformed JSON, a missing field, a duplicate name, a
check with zero or two keys, an unknown check key, a regular expression that does not compile, a `start` with both or
neither key, a `url` that is not http or https, `maxSteps` out of range, or an `elementAbsent` with no `elementVisible`
beside it in the same list. Nothing runs if any scenario is invalid.

### Pure logic in `NoHandsCore`

A new file, `TaskScenario.swift`, holds the decoding and these pure functions on `ScreenObservation`:

| Check | Holds when |
|---|---|
| `windowTitleContains` | the window title contains the text, ignoring case |
| `urlMatches` | the observation has a URL and the expression matches somewhere in it |
| `elementVisible` | some listed element's title contains the text, ignoring case |
| `elementAbsent` | the element list is not empty and no title contains the text, ignoring case. The list is rarely empty even when a page tree has not built (menu bar and toolbar still list), so file validation also requires an `elementVisible` in the same list, naming something on the page, as proof the page was read |
| `mediaPlaying` | `observation.media == .playing` |

Also pure:

- **Default start state.** For `app`: the frontmost app's name contains the given name, ignoring case, and the window
  title is not empty. For `url`: the observation's URL has the same host and path as the start URL, ignoring a leading
  `www.` and a trailing `/`. Comparing the path keeps an earlier scenario's `youtube.com/watch` tab from counting as the
  `youtube.com/` start while the new tab is still opening. A start URL that redirects is `start-failed`, so the file
  uses the final URL.
- **Verdict**, from how the task ended and whether every check held:

| Task ended | Checks hold | Verdict |
|---|---|---|
| done | yes | `pass` |
| done | no | `false-done` |
| stuck, failed or ignored | yes | `unclaimed` |
| stuck, failed or ignored | no | `fail` |
| stopped | not evaluated | `stopped` |
| never started | not evaluated | `start-failed` |
| suite ended first | not evaluated | `not-run` |

`TaskOutcome` lives in `NoHandsMac`, so core takes its own small enum for how the task ended. `ignored` is not a success
even though its exit status is 0.

- **Report**: the markdown table and summary text from a list of results. Cells are escaped (`|` and newlines) and
  control characters removed.

### The command

`nohands-cli scenarios [file] [--only name]`, with `file` defaulting to `scripts/task-scenarios.json` relative to the
current directory. It lives in a new file beside `main.swift` so `main.swift` gains only the `case`.

Before anything runs: load and validate the file, load the backend (`LLM off` fails as `task` does), check Accessibility,
print the model, backend, Mac model and harness, print a reminder to close tabs left by an earlier run, then wait 3 s. An `--only` name that is not in the file is exit 1.

For each scenario, in file order:

1. **Start.** Bring the app to the front with the existing `activate(appNamed:)` or open the URL in the default browser
   with the existing `open(url:appNamed:)`.
2. **Wait for the start state**, polling a fresh observation once a second for up to 20 s, until the default start state
   and every `ready` check hold. If not, the verdict is `start-failed` and the next scenario runs.
3. **Run the goal** with a new `TaskRunner` built as `task` builds it, from a copy of the config with `maxTaskSteps` and
   `maxMediaTaskSteps` both set to the scenario's `maxSteps`. Step lines print as they do for `task`.
4. **Check.** After the task ends, unless stopped: re-observe as `observe` does (walk once, wait 1 s for a Chromium page
   tree, walk again), then poll once a second for up to 3 s until all checks hold. Print each failing check with the
   title and URL seen.
5. **Print** one line: verdict, steps, wall time from the start of step 3.
6. **Stop any playback.** If the scenario had a `mediaPlaying` check and the final observation lists a Pause control
   (the existing `MediaSignal.control`), click it through the executor, so sound does not run into the next scenario. If
   none is listed, print `still playing`.

Then wait 2 s and go on. At the end, print the summary and the markdown table to stdout.

**Exit status:** 0 when every scenario ran is `pass`, 2 otherwise, 1 for usage or file errors, 130 for a second Ctrl-C.

**The check observer.** `ready`, the final check and step 6 use their own `ScreenObserver`, separate from the task
loop's, which is unchanged. It differs in two ways:

- Its element cap is 300 (the most `AppConfig` allows) on every backend, so a check does not miss a button the model's
  shorter list cut off, and verdicts compare across backends. The native walk still stops at `LabelAssigner`'s 200.
- Its audio probe always answers no, so `media` is `playing` only when a Pause control is on screen. The ordinary
  `Media:` line blends in "another app is making sound", and a video left playing by an earlier scenario would then
  pass a later one. The cost: a player with no accessible Pause control scores `false-done`. The first scenarios all
  use YouTube, which exposes one.

With agent-desktop the check reads the front window only. The native walk (the fallback when agent-desktop cannot read
the window) reads every window of the front app, so a Pause control in a second browser window could count there. Step
6 pauses the suite's own videos for that reason, and the run's header and the note name the harness.

**Ctrl-C.** The first Ctrl-C calls `cancel()` on the running task (or abandons the start wait), marks that scenario
`stopped`, marks the rest `not-run`, prints the summary and exits 2. A second Ctrl-C exits at once with 130, using the
existing `InterruptPolicy`.

### The first scenarios

`example.com` is a neutral start page, so a goal that names a site has to get there on its own.

| Name | Start | Goal | Success | Steps |
|---|---|---|---|---|
| `youtube-latest` | `https://example.com/` | Turn on the latest Outdoor Boys video | URL `youtube\.com/watch`, media playing, element `Outdoor Boys` | 24 |
| `youtube-search-play` | `https://www.youtube.com/` | Search YouTube for how a jet engine works and play the first result | URL `youtube\.com/watch`, media playing, title `engine` | 24 |
| `wikipedia-article` | `https://example.com/` | Open the Wikipedia article for the speed of light | URL `wikipedia\.org/wiki/Speed_of_light`, title `Speed of light` | 12 |
| `site-search` | `https://example.com/` | Open github.com and search it for swift collections | URL `github\.com/search\?.*q=swift` | 12 |
| `textedit-save` | app `TextEdit` | Make a new TextEdit document, type hello from NoHands, and save it as nohands-scenario-{run} | title `nohands-scenario-{run}` | 12 |
| `cookie-banner` | a real site, see below | Dismiss the cookie banner on this page | URL on that site, element visible: a stable link on the page, element absent: the banner's accept button | 12 |

For `cookie-banner` the builder picks one site that shows a consent banner from the US, and sets `ready` to
`elementVisible` of its accept button, so a page that shows no banner is `start-failed` and not a free pass. Once
accepted, the browser remembers it: a rerun is `start-failed` until that site's cookies are cleared. The as-built note
names the site and says this.

### Docs and the first run

- `README.md`: a `scenarios` row in the CLI table, and the same in `usage()`.
- `docs/superpowers/as-built/2026-11-09-task-scenarios.md`: hardware, model, backend, the date and the table from a run
  on the M1 Pro. The note's table has names, verdicts, steps and times only: no window titles or URLs from the screen.

## Testing

Table-driven tests in `Tests/NoHandsCoreTests/`, one per rule: file validation (valid and each rejection), each check
(including `elementAbsent` on an empty list and `urlMatches` with no URL), the default start state, the verdict table,
`{run}` substitution, and report escaping. No test needs a screen, a permission or a model.

Manual, listed in the PR: the live run, Ctrl-C during a scenario, and a second Ctrl-C.

## Calls I made

1. **The live run needs an Anthropic key that is not on this machine now.** `~/.config/nohands/config.json` is `{}` and
   `ANTHROPIC_API_KEY` is unset, so the backend resolves to local (Ollama with `qwen2.5:7b-instruct` is running). The
   ticket asks for the first run on Claude. If a key is present at build time, the run uses Claude. If not, the builder
   runs the suite on the local model, records that in the note, and the PR lists the Claude run under Not proven.
2. **The first run takes over this Mac's screen, mouse and keyboard** for several minutes and leaves browser tabs open.
   The builder runs it once, as the ticket's acceptance requires. Accessibility is already granted to this session.
3. **Ctrl-C ends the whole suite**, not only the current scenario. The ticket says it stops the current scenario "like
   stop"; going on to the next one would grab the screen back from someone who just tried to take it.
4. **`success` is a list of checks, all required**, where the ticket reads as one check per scenario. One check cannot
   tell "the Outdoor Boys video plays" from "some video plays".
5. **Two additions to the ticket's checks and fields:** `elementAbsent` and an optional `ready` list. Dismissing a banner
   can only be checked by its absence, and absence means nothing unless the banner was there first. `ready` also lets a
   scenario refuse to start on the wrong page.
6. **`mediaPlaying` counts a Pause control only, never the audio hint.** A false failure is visible; a false pass from
   a leftover video is not.
7. **Seven verdicts instead of pass and fail.** `false-done` (the model claimed success and the screen disagrees) and
   `unclaimed` (the goal was reached but the task did not end `done`) are the two numbers this suite exists to expose.
8. **"Latest" is not verified.** The check proves an Outdoor Boys video plays, because the newest upload changes and
   the suite has no independent source for it.
9. **Nothing is cleaned up.** Tabs stay open and the TextEdit test leaves `nohands-scenario-<time>` files in TextEdit's
   default folder. The suite pauses playback but does not close anything: it never deletes or closes what a model
   might have put elsewhere. The model can see old tabs, so before a rerun the operator closes the last run's tabs; the
   command prints that reminder, and the title check on `youtube-search-play` keeps the first scenario's tab from
   passing it within one run.
10. **Scenarios run in file order, once each**, with no retries. A flaky pass should look flaky across runs.
11. **Timeouts:** 20 s for the start state, 3 s of polling for the final check, 2 s between scenarios. Left to the builder
    to adjust if the first run shows they are wrong, recorded in the note.
12. **`url` starts accept only http and https**, so a scenario file cannot launch `file:` pages or app URL schemes.
13. **`site-search` allows a direct search URL.** The model may open `github.com/search?q=…` without touching the
    search box, since that is how the existing site search works.
14. **A pre-roll ad counts as playing.** A Pause control shows during an ad, so a `done` called during one passes
    `mediaPlaying`. An ad check would miss unskippable ads and add little.
15. **No completeness signal for screen reads.** A read cut short by the 1 s walk budget is not detected. Requiring a
    visible element beside every `elementAbsent` covers the case that matters without changing `ScreenObservation`.

## Left to the builder

How the new code is split between files, the exact console format, and the choice of cookie-banner site.
