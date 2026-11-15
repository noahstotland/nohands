# NH-50: Read page text: Plan

**Spec:** [2026-11-15-nh-50-read-page-text-design.md](../specs/2026-11-15-nh-50-read-page-text-design.md)

Test command: `swift test` (typecheck: `swift build`). Tests per `AGENTS.md` § Testing: table-driven, no mic/AX/model.

## Task 1: Core (NoHandsCore)
- `PageText.swift`: `limit` 4000, `nearLimit` 40, `join`, `isGeneric`, `near` (spec § PageText).
- `Action.readPage`; `IntentDecoder` (`read_page`), `IntentSchema` (kind in the no-field Claude branch + prompt line + untrusted list), `ActionSummary`, `SettlePolicy`, `SpokenFreeText`.
- `near: String?` on `UIElementInfo` and `ObservedElement` (default nil); `ClaudeRequestBuilder` renders ` near: "…"` and uses `PageText.limit` for readings starting `page: `.
- Core tests: join, isGeneric, near, userMessage rendering, decoder.

## Task 2: Mac (NoHandsMac)
- `ElementProviding.pageText() -> [String]` (default `[]`); `AXQuery` implementation (500 ms, 4000 nodes, cancellation, visible frames, no fields).
- Observation walker keeps the last static text/heading in browsers' first web area and sets `near` on generic links/buttons; `ScreenObserver`/`LabelAssigner` copy it to `ObservedElement`.
- `ActionExecutor` (+Harness) runs `.readPage`: reading `page: <text>` with 4000 limit, failure `no text on this page`, private-marker log.
- Mac test with a fake provider: one `page:` reading carried to the next request; empty page failure.

## Task 3: Docs
- README note if the action list/CLI tables are affected (not the voice table; no grammar phrase).
