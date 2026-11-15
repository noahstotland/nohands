# NH-91: Model-written plans, run and checked in code — Design

**Date:** 2026-11-08  **Ticket:** [NH-91](https://github.com/noahstotland/nohands/issues/91)
**Status:** Shipped
**Shipped:** in PR #106, as specified

## Intent

"Put on the latest Outdoor Boys video" should finish without the model choosing every step from a long element list. In the 2026-11-08 local run, qwen2.5:7b-instruct wrote the right URL, then clicked the Edit menu three times and ended `stuck`.

The ticket proposed a coded `Route` protocol with a `YouTubeLatestVideo` route. The user rejected it: nothing site-specific is hard-coded. For a goal that looks multi-step, the model writes a short plan once, from a closed set of step types, with a check per step. A generic engine runs it and verifies each check against the screen. On any miss, the normal loop takes over from where the plan got to.

## Goals and non-goals

- A generic plan type, decoder, validator and engine in `NoHandsCore`, with no site names, URLs or page words in code or the new prompt.
- Plan steps run through the same guards, trail, step cap, "stop" and `done` media check as model steps.
- A failed check or step hands over to the loop with the plan's steps as History.
- Non-goals: saved plans (#46), pop-up closing (#42), logins, loop prompt changes (NH-90). The planner sends no screen content.
- Failures even if tests pass: a gated-out goal behaves differently, or a plan says `done` with failed checks.

## Approaches

The model writes the plan and a generic engine runs it (chosen). Rejected: routes as data (each flow written ahead) and a better loop with no plans (overlaps NH-90). The plan is **a step source in the existing loop**, so each step passes every guard.

## How it works

`run(goal)`: first observation as today. `PlanGate.mayPlan` false: normal loop. Otherwise `resolver.plan(goal)`; none, invalid or an error: normal loop. Then each iteration `engine.next(observation)` gives `.step` (runs through the loop body), `.finish` (a `done` step through the existing done path) or `.handOver(reason)` (plan ends, reason on the last History record, the model answers this same step).

**Gate.** A plan request costs a round trip and the local model's cached prefix, so it runs only when the goal has 4+ words; matches `MediaGoal` or names a site; names no browser (plans have no browser field); and has none of `this`, `current`, `here` (the planner cannot see the screen).

**Plan.** JSON `{"plan":[{intent, site, do, text, after, expect:{kind, text}}]}`; `null` or empty means no plan. Every property is required (unused ones are `""`), so Claude's structured output sees no optionals.

- **The model never writes an address.** The 7B invents hosts. `site` is an enum of `SiteSearch.siteNames`, and code builds every address from the site table. A per-step-kind union and an empty-able `site` both made Haiku and Sonnet answer badly, so every step has a non-empty `site`.
- **Step types, the whole set:** `open_site`, `search` (each then waits 1500 ms), `click` (first title match, exact preferred), `click_first_item` (first content link, after the element titled `after` if given) and `wait_for_media` (click Play once if shown, wait up to 20 s).
- **Check kinds:** `title_contains`, `url_contains`, `element_present`, `media_playing`. Every step has one; all but `media_playing` need text.
- **Content link:** a `link` that is not `offscreen`, has 3+ title words, and is not in a **navigation stack** (3+ links with the same left edge and width, rows within the link's height plus 16 points). On a real YouTube Videos tab the sidebar's subscription links precede the first card, so "first multi-word link" clicked a subscription. The rule uses frames from `labels`; where a backend gives none, `click_first_item` hands over.
- **Text matching:** lower-cased, accents folded, letters and digits only, spaces removed, substring.

**Planning request.** One compact request: a short system prompt, a few examples and the goal through `ClaudeRequestBuilder.sanitize`; no app, title, URL or elements. The prompt lists the supported sites, with one site-agnostic rule to prefer the long-video site for a creator's videos (without it the 7B chose a short-clip site). Two examples answer `null` (no plan needed, a Mac app). `IntentResolving.plan(goal:)` defaults to nil. The Ollama body keeps the task step's `num_ctx`, since a different one reloads the model. Any non-cancel error means no plan; a cancel ends `stopped`.

**Plans are untrusted.** The whole plan is rejected, and the loop runs, unless:

- It has 2 to 8 steps, starts with `open_site` or `search` (it never sees its starting screen), and every step and check kind is known.
- Every `site` is in `siteNames`; texts are at most 80 characters.
- At least one check (or `search` text) contains a distinctive goal word: 3+ letters, minus `MediaGoal` words and general words (`latest`, `newest`, `top`, `first`, verbs, articles). So a plan for an invented channel cannot report success.
- A `MediaSignal.wantsPlayback` goal ends with `wait_for_media`. Code appends it when missing, and rejects only if that passes 8 steps.

There is no typing, key, close or menu step. Everything compiles to existing `Action`s through the existing guards.

**Engine (`PlanEngine`).** A pure state machine. Before each step after the first it reads the previous check. A miss emits one `wait 1500 ms` and looks again; a second miss hands over. A missing target gets the same one look. After the last check it returns `.finish`. Hand-over reasons are fixed strings naming step number and check kind, none starting with `no element` or `element changed` (so no vision fallback).

**`TaskRunner`.** The plan request runs before the loop, through `runCancellable` so "stop" aborts. If the last History record has a `failure`, the plan ends. On hand-over the reason goes on the last record if its `failure` is nil, elements are cut to the normal cap, and the model path runs this iteration. `ScreenObserver.observe(limit:)` lets a plan see 200 elements (the local cap of 40 is spent on the menu bar, per #90); the model never sees them. Plan steps share the step cap.

## Known costs

- An outage costs two timeouts (about 24 s on Claude, 60 s local): the plan error is dropped, then the loop meets it.
- On the local model a `null` plan or hand-over costs the roughly 2,200-token cached prefix (3 to 20 s cold on an M1 Pro).
- `click_first_item` can pick the wrong link; the model's check after it is the defence. `Media: playing` can come from Mac-wide audio.

## Build gate: real element lists

The build captured 3+ real pages from different sites (one a video list) with `nohands-cli observe` and `snapshot`, pinned trimmed copies in the test table, and set the content-link threshold from them. If no generic rule worked it was to stop with `BLOCKED:` rather than add a site rule.

## Measuring

**Not delivered as written:** the end-to-end table over 10 goals was not produced (screen locked). The PR reports plan-request results for the same goals instead. No pass bar.

## Docs and tests

README § Multi-step tasks gets a paragraph on planned goals; the privacy section notes the plan request sends only the transcript. Table tests cover the gate, validation, text matching, element picks on the captured lists, the engine, and `TaskRunner` hand-over, "stop" and plan error. Both intent fixture files still pass on Claude.

## Calls I made

1. **Local-model bar relaxed by the user** after the first build missed it (invented hosts): site-based steps, and passing on Claude is allowed since most users use Claude.
2. **Replaces the ticket's `Route` protocol,** by the user's choice. A wrong URL hands over.
3. **The plan is written once from the goal alone,** with no replanning, and a gate limits which goals are planned.
4. **Strict validation over yield:** a wrong video reported `done` is worse than the loop. Code appends `wait_for_media` rather than reject.
5. **No typing, key or close steps;** those stay with the loop's guards.
6. **`click_first_item` uses a generic rule, not a model pick** (picking a number is what the 7B lacks).
7. **No new CLI command or config key.**
8. **Live end-to-end runs not measured:** the screen was locked, so the browser wait failed. The PR lists them under `Not proven`.
9. **The plan request uses the configured model and effort.** Haiku at low effort plans well on the flat schema. The main step schema still fails on Claude until NH-104 merges.
10. **"Latest" is not guaranteed.** Nothing sorts by date; the first search result is the model's best guess.
