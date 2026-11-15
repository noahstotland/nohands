# NH-44: Find on page: Plan

Spec: [2026-11-15-nh-44-find-on-page-design.md](../specs/2026-11-15-nh-44-find-on-page-design.md). Branch
`feat/nh-44-find-on-page`. Verification after every task: `swift build` clean; after tasks 1, 2 and 3 also `swift test`.
Tests follow `AGENTS.md` § Testing: one table per rule, test lines not above feature lines.

## Task 1: core (NoHandsCore, Foundation only)

- `Action.findOnPage(String, movePointer: Bool)`; extend every exhaustive switch (`carriesSpokenText` true, `ActionSummary`
  name and phase "scrolling", anything else the compiler flags).
- `Sources/NoHandsCore/PageFind.swift`: `normalize`, `Matcher` (exact, prefix, contains; first wins in a tier; `offer`
  returns true on exact), `failure(_:)` = `no match for <words> on this page`, `pinFirst(_:found:limit:)`, as in the spec.
- `CommandGrammar`: "find <words>" and "scroll to <words>" (raw words, trailing ASR punctuation trimmed) to
  `.findOnPage(words, movePointer: true)`. Bare "find" and "find the" stay command-F / nil; "scroll to (the) top|bottom"
  and "scroll down" unchanged. Words over 200 characters are rejected by the executor, not the grammar.
- `IntentSchema`: `find` joins `nativeKinds`, carries `target_name`, and gets the prompt line from the spec.
  `IntentDecoder`: `find` with a non-blank `target_name` becomes `.findOnPage(name, movePointer: false)`; else rejected.
- README voice table: rows for `find <words>` and `scroll to <words>`.
- Tests: grammar table, decoder table, one `PageFind` table (matcher order, failure text, pinFirst).

## Task 2: Mac (NoHandsMac)

- `ElementProviding`: `findOnPage(words:) -> UIElementInfo?` and `scrollIntoView(_ element: UIElementInfo) -> CGRect?`
  with nil defaults. `AXQuery` implements them per the spec (800 ms, 6000 nodes, page web area first, skip menus, no
  visibility filter, static text and heading values only, report the enclosing link or button, kAXScrollToVisibleAction
  then re-read the frame for up to 300 ms). Keep the matched `AXUIElement` in `AXQuery` under its lock.
- `ActionExecutor` runs `.findOnPage`: 200-char cap, native walk (with `freshElements`' exposure handling idea), cancel
  checks before the walk result is used and before the scroll, scroll, harness fallback (`harness.find` +
  `.scrollTo(ref:)`), failure messages, `takeFound()`, pointer move only when `movePointer`.
- `TaskRunner` passes `executor.takeFound()` to the next `observe`; `ScreenObserver.observe` applies `pinFirst` to the
  labels (native and harness) and rebuilds the listed elements.
- Tests with a fake provider (extend `Fakes.swift`): offscreen element found and number 1 next; movePointer on/off; no
  match message; cancel scrolls nothing.

## Task 3: close out

- Run `.build/debug/nohands-cli eval` fixtures only if no model needed; otherwise note it as manual. Full `swift test`.
