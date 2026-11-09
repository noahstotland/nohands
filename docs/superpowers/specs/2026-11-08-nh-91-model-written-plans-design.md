# NH-91: Model-written plans, run and checked in code — Design

**Date:** 2026-11-08  **Ticket:** [NH-91](https://github.com/noahstotland/nohands/issues/91)
**Status:** Spec

## Intent

"Put on the latest Outdoor Boys video" should finish without the model having to choose every step from a long element
list. In the 2026-11-08 local run, qwen2.5:7b-instruct wrote the right URL, then clicked the Edit menu three times and
ended `stuck`.

The ticket proposed a `Route` protocol with one coded `YouTubeLatestVideo` route. The user rejected that: the flow must
be dynamic, with nothing site-specific hard-coded, and chose this design. For a goal that looks multi-step, the model
writes a short plan once, from a closed set of step types, with a check for each step. A generic engine runs the plan
and verifies each check against the screen. On any miss, the model's normal loop takes over from where the plan got to.

The model decides what to do once, up front, using what it knows about the site. Code does the part the 7B is bad at:
finding the element and reading whether the step worked.

## Goals and non-goals

Goals:

- A generic plan type, decoder, validator and engine in `NoHandsCore`, with no site names, URLs or page words in code or
  in the new prompt.
- Plans run through the same guards, trail, prompt board, step cap, "stop" and `done` media check as model steps.
- A failed check or step hands over to the normal loop with the plan's steps as History.
- A measured pass rate on the local model and on Claude over 10 goals across several sites, reported in the PR.

Non-goals: learned or saved plans (#46), pop-up closing (#42), sites behind a login, a bigger local model, and changes to
the normal loop's prompt or examples (NH-90). The planner sends no screen content to the model.

Anti-goals, which would make this a failure even if the tests pass:

- A goal the gate rejects gets slower or behaves differently.
- A plan reports `done` when its checks did not pass.
- A plan step skips a guard, the trail, the step cap or "stop".
- A plan can do anything beyond its closed set of step types.
- YouTube, or any other site, appears in the new code or prompt.

## Approaches

1. **The model writes the plan, a generic engine runs it (chosen by the user).** Nothing about any site is in code.
   The risk is that the ticket says a 7B cannot plan five steps, so the local model may often fall back to the loop. The
   build measures this.
2. **Routes as data.** The same engine, with plans from a recipe file. More reliable on a 7B, but someone still writes
   each flow ahead of time. Not chosen. It could be added later on the same engine, and #46 could write the recipes.
3. **No plans, a better loop.** Overlaps NH-90. Not chosen.

Inside approach 1, the plan runs as **a step source in the existing loop**. At the one place the loop asks the model for
the next step, it asks the plan while one is active, and the step runs through everything below that line. A separate
plan runner would duplicate the guards, and every later guard would need adding twice.

## How it works

```
run(goal)
  first observation (as today)
  PlanGate.mayPlan(goal)?  -- no --> normal loop, no extra call
    | yes
  resolver.plan(goal)  -- none, invalid, or error --> normal loop
    | TaskPlan, validated
  for n in 1...maxSteps
    engine.next(observation)
       .step(IntentStep)  --> runs through the loop body unchanged
       .finish(intent)    --> a `done` step with no actions, through the existing done path
       .handOver(reason)  --> plan ends, reason on the last History record, model answers this same step
```

### The gate (`PlanGate`, Core)

A plan request costs a model round trip, and on the local model it displaces the cached prompt prefix. So
`mayPlan(goal:)` is true only when all of these hold:

- the goal has at least 4 words;
- `MediaGoal.matches(goal)` is true, or the goal names a site (a `WebAddress.knownSites` key or a word that looks like a
  domain);
- the goal names no browser. The plan has no browser field, so those goals keep the loop, which honours "in Safari";
- the goal has none of the words `this`, `current` or `here`. The planner cannot see the screen, so a goal about what is
  on it stays with the loop.

These are existing generic signals. A goal that fails the gate runs exactly as today.

### The plan (`TaskPlan`, Core)

```json
{"plan":[
  {"intent":"…","site":"<a supported site>","do":"open_site","text":"","after":"","expect":{"kind":"title_contains","text":"…"}},
  {"intent":"…","site":"<a supported site>","do":"search","text":"…","after":"","expect":{"kind":"url_contains","text":"…"}},
  {"intent":"…","site":"<a supported site>","do":"click","text":"…","after":"","expect":{"kind":"element_present","text":"…"}},
  {"intent":"…","site":"<a supported site>","do":"click_first_item","text":"","after":"…","expect":{"kind":"url_contains","text":"…"}},
  {"intent":"…","site":"<a supported site>","do":"wait_for_media","text":"","after":"","expect":{"kind":"media_playing","text":""}}
]}
```

`{"plan":null}` or an empty list means no plan.

**The model never writes an address.** Live runs showed the local 7B cannot write real page URLs (it wrote invented
hosts, or nothing). `site` is one of `SiteSearch.siteNames` (the sorted keys of `SiteSearch.templates`, the one list); code
builds every address from the site table. The schema makes every property required (an unused `text` or `after` is `""`,
which the decoder reads as absent), so Claude's structured output sees no optional properties. `site` is on every step
and is never empty: it means "the site this step happens on", and code reads it only for `open_site` and `search`. Two
other shapes were tried and dropped, because they failed on the models that matter: a union with one shape per step kind
made Haiku and Sonnet answer with a one-step `wait_for_media` plan, and a `site` that could be `""` made Haiku write
empty sites for searches.

Step types, the whole set:

| `do` | Meaning | Compiles to |
|---|---|---|
| `open_site` | Open a supported site's home page in the default browser | `.openURL(WebAddress.url(for: site))` + `.wait(1500)` |
| `search` | Search a supported site for `text` | `.searchSite(text, site:)` + `.wait(1500)` |
| `click` | Click the first element whose title matches `text`, preferring an exact match | `.click(.label(n))` |
| `click_first_item` | Click the first content link, after the element titled `after` if given | `.click(.label(n))` |
| `wait_for_media` | If the screen shows a Play control and it has not been clicked, click it; then wait for playback | `.click(.label(n))`, then `.waitFor(.mediaPlaying, 20 s)` |

Check kinds, the whole set: `title_contains`, `url_contains`, `element_present`, `media_playing`. Every step must have
one, and every one but `media_playing` must have non-empty text.

A **content link** is a `link` element that is not marked `offscreen`, has at least three words in its title, and is not
part of a **navigation stack**. The build gate showed why the stack test is needed: on a real YouTube Videos tab the
sidebar's links (`Jef. New content available.`, 204 wide, 40 apart, all at the same left edge) come between the `Videos`
tab and the first video card in the native order, so "the first multi-word link after `Videos`" clicks a subscription.
A navigation stack is three or more links with the same left edge and width whose rows are no more than the link's own
height plus 16 points apart. Video cards, search results and file rows are told apart by their spacing, not by any word.
The rule reads frames from the numbered `labels` the runner already holds. Where a backend gives no frames (agent-desktop
without bounds), the stack test cannot run, so the rule is not applied: `click_first_item` hands over, and the build
reports how often that happens. The pinned rows come from the captured real lists
([Build gate](#build-gate-real-element-lists)).

Text matching is the same everywhere: lower-cased, accents folded, letters and digits only, spaces removed, substring.
"outdoorboys" matches "Outdoor Boys - YouTube".

### The planning question

One compact request: a short system prompt with the step types and check kinds, a few examples, and the goal through
`ClaudeRequestBuilder.sanitize`. No app, title, URL or elements are sent.

- The prompt lists the supported sites (interpolated from `SiteSearch.siteNames`) and the schema's `site` is an enum of
  them, so constrained decoding cannot write an address. One rule tells the model to use the site whose main purpose is
  hosting long videos for a creator's videos, a show or an episode. Without it the 7B chose a short-clip site for the
  Outdoor Boys goal. The rule names no site. Examples use only listed sites, vary their step count
  and step types, and name no site flow of their own.
  Two examples answer `null`: a goal that needs no plan, and a goal that names a Mac app rather than a website.
- `IntentResolving` gains `plan(goal:) async throws -> TaskPlan?`, with a default extension returning nil so test fakes
  that do not care need no change.
- `ClaudeRequestBuilder` and `OllamaRequestBuilder` each gain a `planBody(goal:)`. The resolvers reuse their HTTP send,
  deadline and status handling.
- The Ollama body keeps the same `model`, `num_ctx` and `keep_alive` as a task step, because a different `num_ctx` makes
  Ollama reload the model.
- Any error other than a cancel means no plan and the loop runs, so a real outage is reported by the loop's first call.
  A cancel ends the task as `stopped`.

### Plans are untrusted (`TaskPlan.validated`, Core)

The whole plan is rejected, and the loop runs, unless all of these hold:

- It has 2 to 8 steps, and every step and check kind is known. An unknown field value rejects the plan rather than
  dropping the step, so a plan never runs with a hole in it.
- Every `site` is in `SiteSearch.siteNames`; any other value rejects the plan. A `search` has text a search may type.
- Each text field is at most 80 characters and each `intent` is sanitized.
- **At least one check is tied to a distinctive word of the goal.** Distinctive words are the goal's words of three or
  more letters, minus `MediaGoal`'s words and a short fixed list of general words (verbs, articles, and recency words such
  as `latest`, `newest`, `top`, `first`). At least one check's text (or a `search` step's text) must contain one under the matching above. On "watch
  the newest veritasium video", a check on `watch` or `video` does not count and a check on `veritasium` does. A plan for
  a channel or page the model invented cannot be reported as a success.
- **A goal for which `MediaSignal.wantsPlayback` is true must end with `wait_for_media`.** Otherwise a plan could report
  `done` with nothing playing, since the existing `done` path only holds back on `Media: paused`.

The plan has no step that types, presses keys, closes anything or runs a menu command. Everything it does compiles to
existing `Action`s and passes the existing guards. Model output is treated as the `Security overlays` in
`docs/agents/project.md` require.

### The engine (`PlanEngine`, Core)

```swift
public enum PlanMove: Equatable, Sendable { case step(IntentStep), finish(String), handOver(String) }
public struct PlanEngine: Sendable { public mutating func next(_ observation: ScreenObservation) -> PlanMove }
```

A pure state machine over observations.

- Before each step after the first, it reads the previous step's check. On a hit it moves on.
- On a miss it emits one `wait 1500 ms` step and looks again, because pages load late. A second miss hands over.
- A target element that is not found gets the same one extra look, then hands over.
- After the last step's check passes, it returns `.finish`. The loop's existing `done` path then runs, including the
  "not playing yet" look when the goal asks for playback.
- Hand-over reasons are fixed strings naming the step number and check kind. No page text or model text goes in them.
  None starts with `no element` or `element changed`, so they do not trigger the vision fallback by themselves.

### Changes in `TaskRunner`

The merged loop (after #86) has a vision lookup and a `while true` retry around `resolveCancellable`.

- Before the `for` loop, after the first observation: gate, ask (through `runCancellable`, so "stop" aborts it), then
  `if isCancelled { return await finish(.stopped) }`.
- `var request` stays above a new branch, because later code reads `request.vision`. While a plan is active, the branch
  takes the step from the engine. The vision lookup and `while true` move, unchanged, into its `else`.
- At the top of the plan branch, if the last History record has a `failure`, the plan ends without asking the engine. That
  covers an executor failure, a blocked step and `not playing yet`.
- On `.handOver(reason)`: end the plan, put `reason` on the last History record if its `failure` is nil, cut
  `observation.elements` down to the normal cap, and fall into the model path on this same iteration.
- `ScreenObserver.observe` takes `limit: Int? = nil`. While a plan is active the runner passes `TaskPlan.observedElements`
  (200), because the local cap of 40 is spent on the menu bar before page content (measured in #90) and these lists are
  never sent to the model. The cap returns when the plan ends.

Plan steps share the step cap and step numbers with model steps. A plan step carries no point, so the screenshot code
does not touch it.

## Known costs

- **On the local model, a plan answer of `null` or a hand-over costs the cached prefix.** The plan request has its own
  system prompt, so it displaces the ~2,200-token prefix `warmBody` leaves in Ollama's cache, and the next loop step
  prefills cold (3 to 20 s on an M1 Pro, per the `warmBody` comment). The gate limits how often this happens. The build
  records the cost.
- A plan whose first URL is wrong leaves that tab open. `TabGuard` protects the task's own tab anyway.
- `click_first_item` can pick the wrong link. The model-written `url_contains` or `title_contains` check after it is the
  defence, and it is only as good as the check the model wrote.
- `Media: playing` can come from Mac-wide audio when the page shows no player control, so music already playing can pass
  a `media_playing` check. This is the existing signal's limit and this ticket does not change it.

## Build gate: real element lists

No one has read a real page through this walk for this purpose yet. Before writing the content-link rule, the build
captures at least three pages from different sites, one of which is a video list, with the element cap raised to 200.
It captures each page twice, with `nohands-cli observe` on the native walk and with `nohands-cli snapshot` on
agent-desktop. It then:

- pins a trimmed copy of each real list as rows in the test table;
- sets the content-link threshold to what those lists support, with no site-specific words.

If no generic rule picks the right link on those lists, the build stops with `BLOCKED:` and the lists, rather than adding
a site-specific rule.

This is the build's first step. It needs Accessibility for the builder's process and the front of the Mac. If the builder
cannot get them, it stops with `BLOCKED:` and the exact commands for the user to run, before writing the rule.

## Measuring

The build runs these through `nohands-cli task`, on the local model and on Claude, and puts a table in the PR: goal,
whether a valid plan came back, steps run, whether it handed over and at which step, how it ended, and wall time. It
also reports the plan-valid and finished counts for each backend, and the extra latency of the plan request.

1. put on the latest outdoor boys video
2. watch the newest veritasium video
3. play the latest kurzgesagt video
4. put on the latest video from a channel whose handle does not match its name (the handle guess misses)
5. open the top post on reddit right now
6. open the first google result for sourdough starter
7. open the readme of the swift repo on github
8. watch the newest video about the moon landing on youtube
9. open reddit and scroll down a little (a goal the model should not plan, or should plan and hand over)
10. play my liked songs in the spotify app (no plan expected)

The builder may swap a goal that the gate blocks unexpectedly, and says so. The table runs on the default harness
setting, and names which backend each goal used. No pass bar is set here: see the first entry in
[Calls I made](#calls-i-made). Any run the builder cannot make goes in the PR's `Not proven` list.

## Rebasing over open work

- **#86 (NH-41):** merged, and this spec is written against it.
- **#19 (NH-3):** branched from an old main. Its `TaskRunner` hunks are already on main in the same form.
- **#20 (NH-17):** changes `AXQuery` and `ActionExecutor`, which this ticket does not edit.
- **NH-90 (parallel spec):** its guards run on `step.actions` below the new branch, so they apply to plan steps unchanged.
  Its repeat nudge does not fire on plan steps. Its menu-bar sort touches the same few lines of `ScreenObserver` as
  `limit`, a line-level merge. Its example rewrite is in `IntentExamples`, which this ticket does not edit.

The build rebases on `origin/main` at its start and again before opening the PR, and reruns `swift test` after each.

## Docs

README § Multi-step tasks gets a short paragraph: some goals are planned once up front, code runs and checks the plan,
and the normal step-by-step loop takes over on a miss. README's privacy section gains one clause: the plan request sends
only the transcript.

## Tests

One table-driven test per rule, per `AGENTS.md` § Testing.

Core:

- `PlanGate`: passes and rejects, including short goals and a browser name.
- Plan decoding and `validated`: each rejection above, `null`, an unknown step or check kind, a site not in the list, a check tied only to a general word, a playback goal not ending in `wait_for_media`, too many steps.
- Text matching: folded match and miss.
- Element picks: `click` exact over partial, `click_first_item` with and without `after`, on the captured real lists.
- `PlanEngine`: for each step type, the step produced, the extra look, the hand-over reason, `.finish` after the last
  check, and Play clicked at most once.

`TaskRunnerTests`, with the fake resolver and executor:

- A valid plan runs without any `resolve` call and ends `done`.
- A failed check hands over: `resolve` gets the plan's steps as History with the reason on the last one.
- An executor failure on a plan step hands over.
- "Stop" during a plan step ends `stopped`.
- A `plan` error runs the normal loop.
- A goal that fails the gate never calls `plan`.

Both intent fixture files still pass on Claude, unchanged.

## Left to the builder

- Exact names beyond those above, and file layout.
- The wording of intents and of the planning prompt, within the example rule above.
- Whether the plan glue in `TaskRunner` lives in the main file or a small extension, as long as `run` keeps the
  one-branch shape.

## Calls I made

1. **Local-model bar, as decided by the user after the first build.** The user first made "finishes on the local model" a
   hard bar. The first build missed it (the 7B wrote invented hosts). The user then asked for site-based steps (the model
   never writes a URL) and for the goal to be allowed to pass on Claude, saying most users will use Claude: so the local
   bar is no longer the only gate. Both backends are measured and reported. Neither end-to-end result was measured
   (see Calls I made 12).
2. **This replaces the ticket's `Route` protocol and `YouTubeLatestVideo` route**, by the user's choice. The channel
   slot, the channel-filtered search path and the title check against a channel are gone. A wrong URL now hands over to
   the loop rather than trying a coded search.
3. **The plan is written once, from the goal alone.** The model sees no screen when planning and does not replan. A miss
   goes to the normal loop. This keeps the request small and sends no page text to the planner.
4. **A gate limits which goals are planned.** The cost is that a long goal with no media word and no named site never
   gets a plan and runs as today.
5. **A goal that names a browser, or says `this`, `current` or `here`, skips the plan**, since a plan has no browser field
   and the planner cannot see the screen. A goal that names a Mac app is left to the prompt's `null` example. A 7B that
   gets this wrong would open the website instead of the app.
6. **At least one check or search text must match a distinctive word of the goal, and a playback goal always ends by
   waiting for playback.** I chose strictness over yield for the first, because a wrong video reported as `done` is worse
   than falling back to the loop. For the second, code appends the `wait_for_media` step when a model leaves it out
   (rejecting such a plan made the 7B's Outdoor Boys plan fail for no reason). The `done` path still checks playback.
7. **The closed set has no typing, key or close steps.** A plan that would need them is rejected or handed over. This
   keeps the new path small, and those actions stay with the loop and its guards.
8. **Plan steps observe up to 200 elements, and the model never sees them.** On a hand-over the list is cut back first.
9. **Each check and element lookup gets one extra look after 1.5 s**, so a page still loading is not a miss. It costs at
   most one step each.
10. **`click_first_item` uses a generic content-link rule, not a model pick.** Picking a number from a list is the skill
    the 7B lacks. If the rule fails on real lists, the build stops rather than adding a site-specific rule.
11. **No new CLI command and no new config key.** `nohands-cli task` and `observe` cover the measuring.
12. **Live end-to-end runs are not measured.** The Mac's screen was locked during the build (`CGSSessionScreenIsLocked`),
    so no app could come to the front and the executor's wait for the browser failed on every step. The plan-request
    results for the 10 goals are real, from both backends. The PR lists the live runs under `Not proven`.
13. **The plan request uses the configured model and effort as is.** Haiku at low effort plans well on the flat schema
    (checked on five video goals plus a null), so no override was added. Claude's structured output accepts the plan
    schema (it has no optional properties). The main step schema still fails on Claude until NH-104 merges, so a task
    that falls back to the loop fails on Claude for now.
14. **"Latest" is not guaranteed.** A plan searches a site and opens the first result, so the first result for "outdoor
    boys latest" is the model's best guess at the newest video. Nothing in the plan sorts by date. A plan that wants a
    sort can use a `click` step on a sort control the model names, and the check after it decides.
