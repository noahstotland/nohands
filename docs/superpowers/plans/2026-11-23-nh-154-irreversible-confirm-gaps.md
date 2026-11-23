# NH-154 Irreversible confirm gaps: Implementation Plan

> **For agentic workers:** use subagent-driven-development or executing-plans, task by task.

**Goal:** The irreversible-step confirm sees every route to a button, checks the live title at press time, re-reads the screen after a yes, and ends a negation at a comma only when a new instruction follows.

**Architecture:** Pure logic in `NoHandsCore` (`IrreversibleGuard`: route walk, `elementUnder`, `unconfirmed`, `PressGuard`, comma rule); a press-time check in `ActionExecutor` through two new `ElementProviding` methods; `TaskRunner` passes overlay and cursor to `held`, re-observes after a yes and sets `pressGuard`.

**Spec:** docs/superpowers/specs/2026-11-23-nh-154-irreversible-confirm-gaps-design.md (source of truth for routes, messages, negation words, test rows)

## Global Constraints

- Swift 6 strict concurrency; no `@unchecked Sendable`, no `@preconcurrency`; no AppKit/CoreGraphics events/network in NoHandsCore (CGPoint/CGRect value types are already used there).
- `held(_:labels:goal:)` keeps working for `PackFile` and `PackDraft` (new parameters `overlay: OverlayState = .none`, `cursor: CGPoint? = nil`).
- New `ElementProviding` methods get default implementations returning nil; existing fakes compile unchanged.
- Press-time messages: `<verb> not confirmed, look again`; changed screen: `ActionExecutor.elementChanged`. An unknown title lets the press go ahead. Only model task steps set `pressGuard`.
- Test lines must not exceed feature lines; one table-driven test per rule (AGENTS.md § Testing); no test needs Accessibility, the mic or a model. Never edit `scripts/intent-eval*.json` expectations.

## Tasks

1. **Negation (core).** In `IrreversibleGuard.goalVerbs`, a comma ends a negation only when the negated part held no guarded verb form, or the words after it start with just/instead/rather/now/please; `. ; ! ?`, "but", "then" unchanged. New rows in `irreversibleStepsAreHeldUntilTheGoalNamesTheVerb`: "no, send it" allows; "don't send it, just save" holds; "don't delete, send or archive anything" holds; "don't delete it, just send it" allows; existing rows unchanged.
2. **Routes (core).** `IrreversibleGuard.elementUnder(_ p: CGPoint, in: [UIElementInfo]) -> UIElementInfo?` (smallest frame containing p). Extend `held` with `overlay:`/`cursor:` and the spec's route table: grid `numbered` via `GridModel.center(of:)` then elementUnder (labels overlay: its label n; none: label n), `.cursor`/`releaseMouse` under the simulated cursor, `.point`, `moveCursor` also moves the simulated cursor, `focusElement` sets the simulated focus, `drag` checks the `to` end, Return (today) and Space (no modifiers) on the focused button (simulated focus first, else the observed `focused` button). Table rows per the spec's Tests section.
3. **Press-time check (core).** `public struct PressGuard: Sendable { goal: String; confirmed: Set<String> }` and `IrreversibleGuard.unconfirmed(title: String?, guard: PressGuard) -> String?`. Table test: guarded not allowed, allowed by goal, confirmed, unguarded, nil title.
4. **Executor (mac).** `ElementProviding.elementTitle(at: CGPoint) -> String?` and `focusedElementTitle() -> String?` with nil defaults; `AXQuery` implements them (system-wide hit test, climb a few ancestors to a titled one; focused element of the frontmost app). `ActionExecutor.pressGuard: PressGuard?`; before a mouse press (click at a point, mouse-up, drag release), a Return or a Space, and agent-desktop presses, read the title and return `"<verb> not confirmed, look again"` when `unconfirmed` is non-nil. Table test in `ActionExecutorTests` with a fake (cursor click on Send refused, allowed when confirmed, allowed when title unknown, Space on focused Send refused). Extend the existing fake in `Fakes.swift`.
5. **TaskRunner (mac).** Pass `overlay.state` and the executor's current pointer to `held`; set `executor.pressGuard` for the step (goal plus confirmed verbs) and clear it after. After a yes, re-observe; run on the fresh labels only if every label number the step uses keeps its title and role and `held` on the fresh read asks only about confirmed verbs, else record the step failed with `ActionExecutor.elementChanged` and continue the loop. New `TaskRunnerTests` case: observation changes during the wait (renamed to Delete: nothing clicked, failure recorded; moved: click lands at new frame; unchanged: clicks as today).
6. **Docs.** `docs/tasks.md` § Confirmation guard: guarded routes, re-read after a yes, press-time failure message; the NH-61 as-built's last sentence points to the NH-154 spec.
7. Verify: `swift build`, `swift test`, intent fixtures via `nohands-cli eval` if buildable offline (they need a model; skip and say so).

## Review Focus

A step with several actions where an earlier one moves the cursor; stale label numbers after the re-read; a held verb the user confirmed then covered by press-time (confirmed set must be the verbs asked); nil title never blocks; grammar commands and packs never get a `pressGuard`; "stop" still halts during the post-yes re-read; `PackFile`/`PackDraft` results unchanged.
