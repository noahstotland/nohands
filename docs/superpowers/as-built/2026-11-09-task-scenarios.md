# As-built: NH-49 task scenario suite

**Shipped:** in PR #N
**Ticket:** NH-49
**Spec:** [2026-11-09-nh-49-task-scenarios-design.md](../specs/2026-11-09-nh-49-task-scenarios-design.md)

## First run

2026-11-09, MacBook Pro `MacBookPro18,3` (M1 Pro), agent-desktop 1.1.0 as the harness, Chrome as the default browser.

The backend was the **local model, `qwen2.5:7b-instruct`**, not Claude: no Anthropic key was set on this Mac. The Claude run the ticket asks for has not happened.

| scenario | verdict | steps | time |
|---|---|---|---|
| youtube-latest | fail | 0 | 35.4 s |
| youtube-search-play | fail | 0 | 39.5 s |
| wikipedia-article | pass | 1 | 37.0 s |
| site-search | fail | 0 | 34.4 s |
| textedit-save | fail | 0 | 45.2 s |
| cookie-banner | start-failed | 0 | 0.0 s |

1 of 6 pass. The four `fail` rows with 0 steps are the local model timing out on its first request (`status: timed out`, the 30 s `localLlmDeadlineMs`), the same cold-start failure the README describes for this model. They say nothing about the suite's checks or about Claude. The one `pass` was a single `open_url` to the Wikipedia article.

`cookie-banner` is `https://www.forbes.com/` with the accept button guessed as `Accept All`. It never showed that button in 20 s, so it scored `start-failed`. The site and button title are unverified; a rerun needs a site and title checked by eye first. Once a banner is accepted the browser remembers it, so a rerun on the same site is `start-failed` until its cookies are cleared.

## Differs from the spec

- The spec had step 6 print `still playing` when a scenario with a `mediaPlaying` check ended with no Pause control listed. The check observer counts only Pause controls, so no control means not playing, and the line printed on runs where nothing played. It is removed; step 6 only clicks a Pause control when one is listed.
- `ScenarioFile.load` also rejects empty check text (`elementVisible ""` would pass on any page), and the command rejects a file with no scenarios.
- `loadResolver`, `ms`, `runOverlay` and `sanitized` moved from `main.swift` to `CLIHelpers.swift`, unchanged: the compiler crashed when another file called functions declared after `main.swift`'s top-level statements.
- Polling by `freshObservation()` takes about 1 s plus the walk, so an attempt is slightly over a second. The 20 s and 3 s limits are wall-clock deadlines, and the final check always looks at least once.
- The exit status is 0 only when every scenario is `pass`, so `start-failed` and `not-run` also exit 2.

## Checks that didn't run

- The suite on Claude.
- A second pass after the local model is warm.
- Ctrl-C during a scenario, and a second Ctrl-C.
- `youtube-latest`, `youtube-search-play`, `site-search` and `textedit-save` reaching their checks with a model that answers. Their `mediaPlaying` and pause-click paths were not exercised.
