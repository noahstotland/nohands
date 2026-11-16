# NH-7: Fix the deferred minors from the PR #2 harness review: Design

**Date:** 2026-11-16  **Ticket:** [NH-7](https://github.com/noahstotland/nohands/issues/7)
**Status:** Shipped
**Shipped:** in PR #147, as specified

## Intent

PR #2's review deferred five minor findings. Checked against `main` at 558e4a6, two are already fixed and three are still live. This PR fixes the three live ones.

| # | Finding | On main | Action |
|---|---|---|---|
| 1 | Dead `Windows:` line in `ClaudeRequestBuilder.userMessage` | Removed by NH-42 (#65); windows reach the model through the `Tabs:` block | Closed with a [ticket comment](https://github.com/noahstotland/nohands/issues/7#issuecomment-6918550721) |
| 2 | `Settle` reports settled while a value ticks | Replaced by `SettleWatch` in NH-38 (#124), with ticking-value tests in `TaskGuardsTests` and `TaskRunnerTests` | Closed with the same comment |
| 3 | `DesktopCommand` cannot express a negative `--xy` | Live: `drag` sends `--from-xy -100,50`, which agent-desktop parses as a flag | Fix |
| 4 | Traced session left open when a task ends on "stop" | Live: see below | Fix |
| 5 | `AgentDesktopClient.run` pins a pool thread in `waitUntilExit` | Live: the wait runs in `Task.detached`, which is the cooperative pool | Fix |

## Scope

Non-goals: other agent-desktop commands' argument forms; a session started by a `startSession` call that a stop cancelled mid-flight (agent-desktop may have created it, but NoHands never got its ID; rare and harmless beyond a stale trace).

Anti-goals: the HUD waiting on agent-desktop after "stop" (it already shows "stopped" before the session ends, and that order stays; the run itself now ends only after `session end` returns, bounded by the agent-desktop deadline); new `@unchecked Sendable` or `@preconcurrency`; a test that spawns a real agent-desktop.

## Design

### 3. Negative `--xy` (`DesktopCommand`, NoHandsCore)

`agent-desktop drag --help` says: "write a negative value with = (`--from-xy=-100,50`)". `drag` always sends the joined form, `--from-xy=x,y` and `--to-xy=x,y`, so one argument works for any sign. Rounding stays as is. `-0` cannot occur: `Int(p.x.rounded())` gives `0`.

### 4. Session left open on "stop" (`TaskRunner`, NoHandsMac)

"stop" calls `runner.cancel()` and cancels the pipeline's Swift task (`VoicePipeline.swift:405`, `:473`). `finish(.stopped)` then calls `harness.endSession(id)` from a cancelled task. `AgentDesktopClient.run`'s cancellation handler fires at once, so the `session end` child is killed or never spawned, and the traced session stays open.

Fix: `finish` ends the session in an unstructured `Task { await harness.endSession(id) }` and awaits its value. An unstructured task does not inherit cancellation, so `session end` runs to completion under its normal deadline. `finish` still clears `sessionID` first and still runs after the HUD update.

### 5. Pool thread pinned (`AgentDesktopClient`, NoHandsMac)

`Child.launch` blocks in `p.waitUntilExit()` (and in `Reader.finish`'s semaphore wait). It runs in `Task.detached`, which takes a thread from Swift's cooperative pool; a few slow agent-desktop calls at once can starve every other task on the pool.

Fix: run `launch` on a GCD global queue and bridge it back with `withCheckedContinuation`. GCD can add threads when one blocks; the cooperative pool cannot. The cancellation handler, deadline timer and `Child` locking are unchanged. No new `@unchecked Sendable`: `Child` and `Reader` already are, and the continuation is `Sendable`.

## Tests

- `DesktopCommandTests`: one row in the existing drag test for negative coordinates on both ends (`--from-xy=-100,50`, `--to-xy=-3,-4`); the existing positive rows change to the joined form.
- `TaskRunnerTests`: a traced task stopped by cancelling its Swift task ends its session, and the fake harness sees `endSession` called from a task that is not cancelled. Fails today.
- Item 5 gets no new test: the existing `AgentDesktopClientTests` (timeout, cancel, decode against a shell-script stand-in) cover that behavior is unchanged. Pool starvation cannot be shown reliably in a unit test.

## Calls I made

- Closed items 1 and 2 with a ticket comment rather than code; the ticket allowed that and they are fixed on `main`.
- `drag` always sends the `=` form, not only for negative values: one code path, and agent-desktop accepts it for every value.
- The session end runs in a fresh unstructured task that `finish` awaits, rather than fire-and-forget: a later task's `startSession` cannot race a `session end` still in flight.
- The blocking wait moves to a GCD global queue rather than being rewritten around `terminationHandler`: a smaller diff that keeps the tested timeout, cancel and grandchild-pipe handling as is.
- The `startSession` cancelled mid-flight case is left out (see Non-goals).
