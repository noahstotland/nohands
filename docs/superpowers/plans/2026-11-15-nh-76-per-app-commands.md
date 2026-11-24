# NH-76: Per-app voice commands: Plan

Spec: [design](../specs/2026-11-15-nh-76-per-app-commands-design.md). Tests per `AGENTS.md` § Testing: one table-driven test per rule; no test needs Accessibility.

## Task 1: Core packs and phrase lead
- `Sources/NoHandsCore/AppPack.swift`: `AppPack`, `AppPacks.all = []`.
- `CommandGrammar`: init takes `packs: [AppPack] = AppPacks.all`; `parse(_:frontmost:)` (default nil) with the lookup order in the spec; `PhraseLead.strip`. Keep "stop" untouched.
- Tests (`Tests/NoHandsCoreTests`): pack precedence per bundle ID, shared normalization, "menu <words>", unknown "open x" still `.openApp`, `AppPacks.all` has no stop phrase or empty actions.

## Task 2: Menu matcher
- `Sources/NoHandsCore/MenuMatch.swift`: `MenuEntry`, folding, exact / starts-with / contains-all tiers, path limit, no match. Table-driven test.

## Task 3: Mac menu path
- `MenuReading` protocol + `AXMenuReader` (skips Apple menu, 200 ms / 1500 items). `ActionExecutor` `.menuItem`: native first, then harness, else "no menu item called …"; disabled message. Fake reader test.
- `VoicePipeline`: pass frontmost bundle ID into `modeMachine.route` and the merge buffer closures (updated on app activation).

## Task 4: CLI and README
- `nohands-cli parse --app`, `menu "<words>"`, `menu --list`. README rows and "Per-app commands" section.

## Task 5: Verify
- `swift build`, `swift test`, intent fixtures unchanged. AXPress check on macOS 14 is manual (PR Proof).
