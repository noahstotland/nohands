# NH-155 menu bar `click_in` guards: Implementation Plan

**Goal:** `.clickIn(.menubar, name)` gets the quit, close and Apple menu checks `.menuItem` gets, plus the `MenuBarGuard` top-level check.

**Spec:** docs/superpowers/specs/2026-11-23-nh-155-menubar-click-in-guards-design.md

## Global Constraints

- Swift 6 strict concurrency; no AppKit in NoHandsCore. One copy of the quit/close title rule (shared helper in `ShortcutGuard`).
- Tests: one table per rule (AGENTS.md § Testing); none for the executor (needs agent-desktop).

## Tasks

1. `ShortcutGuard`: extract `menuTitleBlocked`; add the `.clickIn(.menubar, …)` case with the Apple and lookalike refusal. Table test.
2. `MenuBarGuard`: refuse `.clickIn(.menubar, name)` on a disallowed top-level title, badges or not. Table test.
3. Executor: on `.menubar`, refuse an Apple or lookalike found item, and on a model step one whose title differs from the named one.
4. Verify: `swift build`, `swift test`.

## Review Focus

Badge exception must not apply to `click_in`; the executor backstop must not break the user's own `click_in` (no `labelSnapshot`); no other surface changes.
