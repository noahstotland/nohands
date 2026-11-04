# NoHands Task Agent — Design

**Date:** 2026-11-04  **Status:** approved (user opted to dive in; choices below are the builder's calls)

## Intent

Let the user state a goal in natural language ("open Veritasium's latest video") and have NoHands carry it out across several screens: open Chrome, reach YouTube, find the channel's newest video, play it. Today every LLM request is one shot — transcript plus the frontmost app's control titles in, a fixed action list out, executed blind. Goals whose next step depends on what the screen shows cannot be scripted in advance, so they fail.

Both backends must work: Claude over the API (better) and free open-weight models through Ollama (slower, weaker, private). The user accepts slower execution for complex tasks but wants simple commands to stay fast.

## Goals / non-goals / anti-goals

- **Goals:** observe→act→observe loop; same step schema for Claude and Ollama; simple commands cost exactly one model call as today; the user can stop a running task by voice; the loop cannot run away (step cap, repeat detection, per-step deadline).
- **Non-goals (this pass):** screenshots / vision models; persistent memory across tasks; asking the user clarifying questions mid-task; parallel tasks.
- **Anti-goals:** typing or clicking after the user said stop; an endless loop against a page that never changes; silent failure — "stuck" must be said out loud (HUD) with the model's reason.

## Approaches considered

1. **Scripted multi-step in one shot (status quo).** Model emits the whole action list up front. Fails whenever the next step depends on page content. Rejected.
2. **Observe→act loop on top of the existing resolver/executor, screen read through accessibility.** Each step: observation (app, window title, URL if a browser, numbered elements with roles) + goal + history → model returns `{intent, status, actions}`. `done` on step 1 is exactly today's one-shot path, so simple commands pay nothing extra. Chosen.
3. **Vision agent (screenshot per step).** More robust on pages with poor accessibility, but needs a vision-capable model on both backends, is slower, and sends pixels off-machine on the Claude path. Deferred; the loop's `ScreenObservation` is the seam a vision observer would plug into later.

## Design

### Step contract (both backends)

Request (rebuilt from scratch every step; no server-side conversation state):

```
Goal: <transcript of the original request>
Step: <n> of <max>
History:
  1. <intent> -> [kinds] (ok | FAILED: <message>)
  2. ...
App: <frontmost app>   Window: <focused window title>   URL: <web area URL or ->
Mode: command   Overlay: none|grid|labels
Visible elements:
  3 [button] Back
  9 [link] Veritasium — How Electricity Actually Works
  ...
Request: <goal again on step 1; on later steps the line is "Continue toward the goal.">
```

Response schema, in this property order (order is what makes a constrained local decoder restate before acting):

```json
{"intent": "one sentence", "status": "continue|done|stuck|ignore", "actions": [ ... ]}
```

- `continue`: run `actions`, wait for the screen to settle, observe again, ask again.
- `done`: run `actions` (may be empty), then finish. The HUD shows the intent.
- `stuck`: run nothing; HUD shows the intent (the model's explanation).
- `ignore`: not a computer action; run nothing (same as today).
- New action kind `wait` with `ms` (clamped 100…5000): sleep, for pages that are still loading.

### Loop (`TaskRunner`, NoHandsMac, main actor)

1. Observe. 2. Resolve one step (deadline `llmDeadlineMs`). 3. If `done`/`stuck`/`ignore` → execute (done only) and finish. 4. Execute `actions`; a failure is recorded in history as `FAILED: <message>` and the loop continues (the model gets to react). 5. Settle: poll the observation every 250 ms until two consecutive snapshots have the same element titles, min 300 ms, max `settleMs` (default 3000). 6. Repeat from 1 until `maxTaskSteps` (default 12) → finish as stuck "step limit reached". Three consecutive steps with identical `actions` → stuck "repeating the same action".

Cancellation: `TaskRunner.cancel()` sets a flag checked before every execute and every resolve; an in-flight HTTP request is cancelled via the existing `IntentHTTP` race. A held mouse button is released on any exit.

### Pipeline integration

The consumer must stay responsive while a task runs. `VoicePipeline` keeps the serial job stream but runs the task in a child `Task`; jobs that arrive meanwhile are routed: a stop phrase (`StopWords.isStop`: "stop", "stop it", "cancel", "cancel that", "never mind", "nevermind", "abort", "halt") cancels the task and shows "stopped"; any other utterance is held (newest one only) and handled after the task ends. The grammar fast path and dictation mode are unchanged.

HUD: each step shows `step n · <intent>` for the step's duration; finish shows `done`, `stuck: <intent>`, or `stopped`.

### Observation (`ScreenObserver`, NoHandsMac)

Built on `AXQuery`. Adds: focused window title (`kAXTitleAttribute` of `kAXFocusedWindowAttribute`), web URL (first `AXWebArea`'s `AXURL`, or the window's `AXDocument`), element roles, and up to `maxObservedElements` (default 120) titled elements in reading order (LabelAssigner numbering). For Chromium browsers, set `AXManualAccessibility` = true on the app element once per app so the page tree is exposed. Static text is not included (only actionable roles) to keep the prompt small; the window title and URL carry the page identity.

### Backends

- Claude: `output_config.format` with the step schema; `max_tokens 1024`; effort from config (default medium); deadline `llmDeadlineMs` (default 12000, was 4500).
- Ollama: same schema via `OrderedJSON` so `intent` precedes `status` precedes `actions`; few-shot examples rewritten in the step format, including one two-step example (continue → done) so the model has seen history. Deadline `llmDeadlineMs`.
- `IntentResolving.resolve(_ request: StepRequest) async throws -> IntentStep`. One-shot callers (eval, CLI) send step 1 and read `step.actions`.

### Prompting (system prompt additions)

The model controls the Mac step by step and will see the screen again after its actions run. Prefer deterministic routes: type a URL (`youtube.com/@veritasium/videos`) over clicking through menus; use `wait` after navigation if the page is not there yet; on YouTube the newest upload is the first video on a channel's Videos tab; set `done` once the goal is visibly achieved; set `stuck` with a plain reason rather than guessing; never repeat an action that failed without changing something.

### Config (new keys, all optional)

`maxTaskSteps` (12, 1…30), `llmDeadlineMs` (12000, 2000…60000), `settleMs` (3000, 0…10000), `maxObservedElements` (120, 10…300).

### Safety

Step cap, repeat detection, stop phrase, per-step deadline, `maxTypedCharacters` unchanged, no new permissions. Element titles, window titles and URLs remain untrusted data in the prompt (existing rule 5).

## Left to the builder

Exact AX attribute fallbacks per browser; HUD durations; whether the CLI `task` command needs a `--dry-run` (it does not; `resolve` already shows step 1 without executing).
