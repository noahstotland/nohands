# NH-53: Browser tabs by name and number: Plan

Spec: [2026-11-15-nh-53-browser-tabs-design.md](../specs/2026-11-15-nh-53-browser-tabs-design.md). Branch
`feat/nh-53-browser-tabs`. Verification after every task: `swift build` clean; after tasks 1 and 2 also `swift test`.

## Task 1: phrases, actions and matcher (NoHandsCore)

- `Action.swift`: `TabTarget` (`number(Int)`, `last`, `named(String)`) and `goToTab(TabTarget)`, `closeOtherTabs`,
  `listTabs`. Add them to every exhaustive switch (`ActionSummary` kinds and spoken text, `SettlePolicy`,
  `SpokenFreeText`, `PipelineText` if it switches). `IntentDecoder` gets no kind for them.
- `BrowserTabs.swift`: `TabMatch.best(_:in:)`, `TabMatch.chord(for:)`, `TabMatch.listLine(_:)` as the spec says.
- `CommandGrammar.parse`: `parseTab(tokens, transcript)` after the `menu` rule and before `parsePattern`, per the
  spec's phrase table, including the reserved name words and the 1 to 99 range.
- Tests, table-driven: grammar phrases and must-not-change rows in `CommandGrammarTests`; `TabMatch.best`, `chord` and
  `listLine` in `BrowserTabsTests`.

## Task 2: executor (NoHandsMac)

- `ActionExecutor`: `.goToTab`, `.closeOtherTabs`, `.listTabs` per the spec's Executor section: browser check first;
  chord when `TabMatch.chord` has one; otherwise read `browserWindows()` in a detached task, check cancellation,
  `selectBrowserTab(id:)`; `closeOtherTabs` through `pressMenuItem("Close Other Tabs", exactOnly: true)`; `listTabs`
  through `showHUD(_, duration: .seconds(6))`. Failure messages as in the spec. Titles are never logged.
- Tests with `FakeElements` / `FakeInput` / `FakeOverlay`: one table-driven test covering a named switch selecting the
  right tab id, a chord number pressing command-n with no tab read, not-a-browser failing with no press, n past the end.

## Task 3: README

- Rows in the voice command table for each new phrase, with the browser-only note and the Close Other Tabs caveat.
- Manual checks (Safari, Chrome, Firefox, Finder) go in the PR under Not proven.
