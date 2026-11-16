# NoHands Task Agent — Design

**Date:** 2026-11-04  **Status:** approved (user opted to dive in; choices below are the builder's calls)

## Intent

The user states a goal ("open Veritasium's latest video") and NoHands carries it out across several screens, on Claude or Ollama. One-shot requests fail when the next step depends on the screen. Complex tasks may be slower; simple commands stay fast.

## Goals and limits

- An observe, act, observe loop with one step schema for both backends; simple commands cost one model call.
- A voice "stop" ends a task, with no typing or clicking after. The loop can't run away (step cap, repeat detection, per-step deadline). "Stuck" is shown in the HUD with the model's reason.
- Non-goals: vision, memory across tasks, mid-task questions, parallel tasks.

## Approaches

- **An observe-act loop on the existing resolver and executor, reading the screen through accessibility** (chosen).
- A whole action list up front: rejected. A vision agent: deferred (sends pixels off-machine).

## Design

- **Step contract.** Each request is rebuilt: goal, step number, history, app, window title, URL, numbered elements. The response is `intent`, `status`, `actions` in that order, so a local decoder restates before acting.
- **Status:** `continue` runs actions and observes again; `done` runs actions and finishes; `stuck` runs nothing and shows the reason; `ignore` is not a computer action. New action `wait` with `ms` clamped 100 to 5000.
- **Loop** (`TaskRunner`): a failed action goes into history and the loop continues. Settle polls every 250 ms until two snapshots have the same element titles (min 300 ms, max `settleMs`). The step cap ends it as stuck "step limit reached"; three identical consecutive `actions` end it as "repeating the same action".
- **Cancel** is checked before every execute and resolve, cancels an in-flight request and releases a held mouse button. Other utterances wait (newest only).
- **Observation** adds window title, web URL and up to `maxObservedElements` titled elements. Static text is left out to keep the prompt small.
- **Backends.** Claude: `max_tokens` 1024, `llmDeadlineMs` 12000 (was 4500). Ollama: few-shot examples in step format.
- **Config:** `maxTaskSteps` (12, 1…30), `llmDeadlineMs` (12000, 2000…60000), `settleMs` (3000, 0…10000), `maxObservedElements` (120, 10…300).
- **Safety:** no new permissions; screen text stays untrusted data.
