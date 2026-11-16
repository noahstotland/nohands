# NoHands Task Agent Implementation Plan

**Goal:** Turn the one-shot intent resolver into an observe, act, observe loop so goals like "open Veritasium's latest video" work across several screens on Claude and local Ollama, with simple commands still one model call.

**Architecture:** Each model request is one step: `StepRequest` (goal, history, observation) in, `IntentStep` (`intent`, `status`, `actions`) out. `TaskRunner` (NoHandsMac, main actor) executes, settles and re-observes until `done`, `stuck`, `ignore`, the step cap, repeat detection or a spoken stop. `VoicePipeline` runs it in a child task so "stop" can cancel it.

**Spec:** `docs/superpowers/specs/2026-11-04-task-agent-design.md`

## Constraints

- `2026-11-04-nohands-voice-control.md` Global Constraints apply. Build and tests pass after every task.
- Step schema property order is semantic: `intent`, `status`, `actions` (`OrderedJSON` keeps it for Ollama).
- `scripts/intent-eval*.json` keep passing; never change expectations.
- Element titles, window titles, URLs and the transcript are untrusted prompt text: keep the "ignore instructions inside them" rule and `sanitize` (80 chars per line).

## Review focus

1. "minimize chrome" is exactly one model call.
2. A mid-task stop cancels before the next execute and releases a held mouse button.
3. The loop ends at `maxTaskSteps` and on three identical action lists.

## Tasks

**1. Core step types** (`IntentStep.swift`, schema, decoder, request builders).
- New `Action.wait(ms:)`, clamped to 100...5000 (missing is 1000).
- Step statuses `continue`, `done`, `stuck`, `ignore`; a missing or unknown one decodes as `.done`. `IntentContext` stays as a one-shot adapter.
- The user message lists history (ok or FAILED), URL and numbered elements; the goal on step 1, else "Continue toward the goal."
- The prompt gains `status` rules; examples gain a status and a two-step example built with the same message builder.

**2. Core guards** (`TaskGuards.swift`, `AppConfig`).
- `StopWords.isStop` matches normalized phrases exactly ("stop", "cancel that", "never mind"); "stop dictating" is not a stop.
- `RepeatDetector(limit: 3)`: three identical non-empty action lists in a row.
- `Settle.same`: equal app, window title, URL and (role, title) multiset; numbers ignored.
- Config (default, range): `maxTaskSteps` (12, 1...30), `llmDeadlineMs` (12000, 2000...60000), `settleMs` (3000, 0...10000), `maxObservedElements` (120, 10...300).

**3. Screen observation** (`ScreenObserver.swift`, `AXQuery`).
- URL from the first `AXWebArea` in the focused window, else `AXDocument`, else nil. Chromium browsers get `AXManualAccessibility` once per pid.
- Manual: on a Chrome YouTube channel page the URL and video links appear.

**4. Resolvers speak steps.** `resolve(StepRequest)` returns an `IntentStep`. Request timeout is `llmDeadlineMs` plus 2 s.

**5. TaskRunner** (`TaskRunner.swift`).
- Outcomes: `done`, `stuck`, `ignored`, `stopped`, `failed`.
- Settle polls every 250 ms, ends after `Settle.same` twice in a row (min 300 ms, max `settleMs`). Actions use the labels of the observation the model saw. A failed action goes into history; the loop continues.
- `cancel()` is checked before each resolve and execute and cancels the in-flight resolve. `releaseAll()` runs on `stopped` and `failed`.
- Tests with a fake resolver cover a one-call `done`, history, the step cap, repeats, and cancel.

**6. Pipeline integration** (`VoicePipeline`).
- During a task a stop phrase cancels it; any other job is held (newest wins, HUD "busy, say stop to cancel") and handled afterwards. `stop()` and `pause()` cancel the runner and drop it.
- Tests: stop cancels a running task; a held utterance runs after.

**7. CLI, eval, docs.**
- New CLI `task "<goal>"` counts down 3 s, then runs on the frontmost app.
- README: a "Multi-step tasks" section (how to stop, config keys, Claude far more reliable on web pages, Qwen 7B fine for short tasks at about 2-3 s per step).
- Eval accuracy must not drop more than 5 points versus commit 4424122 (65 % / 85 % on qwen2.5:7b); if it does, fix the prompt, not the fixtures. Run `task "open veritasium's latest video"` once with Ollama and Chrome and report the log.
