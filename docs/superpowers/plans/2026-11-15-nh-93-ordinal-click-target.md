# NH-93: Ordinal click target: Plan

Spec: [2026-11-15-nh-93-ordinal-click-target-design.md](../specs/2026-11-15-nh-93-ordinal-click-target-design.md). Branch
`feat/nh-93-ordinal-click-target`. Verification after every task: `swift build` clean; after tasks 1 and 2 also `swift test`.

## Task 1: parse and pick (NoHandsCore)

- `Sources/NoHandsCore/OrdinalTarget.swift` (Foundation only): `OrdinalTarget.parse(_:)` and
  `OrdinalTarget.label(in: [Int: UIElementInfo]) -> Int?`, exactly as the spec's Parse and Candidates sections say
  (ordinals first..tenth, `Nth` suffix forms, `last`; optional leading "the"; noun of at most two words; role nouns
  link/button/checkbox/tab/field/text field/box/menu item narrow by role with the `AX` prefix and case dropped; every
  other noun means results: role `link`, title of at least three words, a title equal to the previous candidate's
  dropped; never match the noun against titles). Plural nouns accepted.
- `TargetResolver.element` takes `labels: [Int: UIElementInfo]?`. On a `find(named:)` miss, an ordinal that maps to a
  label (over `labels`, else `LabelAssigner.assign(elements)`) returns that element's click point. An ordinal that does
  not map fails with `no element named '<name>'; say its label number from the list`; other names keep the plain message.
  Both `resolveClick` and `resolveMove` pass `labels`.
- Tests in `Tests/NoHandsCoreTests/TargetResolverTests.swift`: one table over a fixed list (menu-bar items, toolbar
  buttons, address field, tab buttons, short nav links, three results each with a thumbnail and title link of the same
  name) covering the spec's Tests section, plus one `resolveMove` case. No separate parser test.

## Task 2: executor and prompt (NoHandsMac, NoHandsCore)

- `ActionExecutor` click: for `.element(name)` where `find` over the fresh walk misses and the name is an ordinal that
  maps to label n in `labelSnapshot`, run the click as `.label(n)` (existing harness-ref path, else point). Otherwise
  unchanged. `move_cursor` stays on the resolver.
- `IntentSchema.systemPrompt` rule 3: add one sentence, for "the first video", "the second result" or any position, use
  target_kind "label" with that element's number from the list; never put an ordinal in target_name.
- One test in `Tests/NoHandsMacTests/ActionExecutorTests.swift`: an ordinal with a harness ref clicks through the
  harness like a label. Check for any prompt-text test that pins rule 3 and keep it passing.

## Task 3: docs

- If the `README.md` voice command table lists click-by-name phrases, add the ordinal phrases there.
- Run both intent fixtures only if the CLI and a key are available; otherwise list them under Not proven.
