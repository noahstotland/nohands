# NH-46 route memory: plan

Spec: `docs/superpowers/specs/2026-11-16-nh-46-route-memory-design.md` (approved). Branch `feat/nh-46-route-memory`.
Test command: `swift test` (no mic, Accessibility or model). Typecheck: `swift build`. Tests follow `AGENTS.md` § Testing: one table-driven test per rule; test lines must not exceed feature lines.

## Task 1: core store logic
- Add `Sources/NoHandsCore/RouteMemory.swift`: `Route`, `RouteStep` (Codable, Equatable, Sendable), `RouteMemory.steps(from:names:)`, `saving(_:into:)` (replace same goal key and host; cap 50, oldest dropped), `match(goal:currentHost:in:)` (filler words dropped, score = shared / larger set, at least 0.6 and 2 shared, host rule, newest on tie), `decode(Data?)` (never throws; wrong version or bad JSON gives empty), `encoded()`.
- Action strings: snake_case kind plus a name for a target; typed/searched/set text never stored; URLs keep host and path only; failed steps dropped; question steps keep the question, never the answer.
- Test: `Tests/NoHandsCoreTests/RouteMemoryTests.swift` (matching table, steps table, round trip / invalid / cap / replace).

## Task 2: request block and config
- `StepRequest.pastRoute: Route?` (default nil). `ClaudeRequestBuilder.userBlocks`: block after History, repeat note and Site routes, before `App:`; skipped when `playbooks: false`; every string sanitized and `unmarked`.
- `AppConfig.routeMemory: Bool` default true, non-bool falls back.
- Tests in the existing `ClaudeRequestBuilderTests` and `AppConfigTests`.

## Task 3: grammar
- Phrases `forget that route` and `forget all routes` (also with the attention word) route to a new `Routing.forgetRoutes(all: Bool)` from `ModeMachine`, command mode only. Never reach the model. Handle the new case in every `switch` on `Routing`.
- Test in `ModeMachine`/grammar tests (one table).

## Task 4: mac
- `NoHandsMac/RouteStore.swift`: like `CommandLogStore` (load once, in-memory list, serialized background writes via `ConfigFile.writePrivateFile`, mode 600, bad file gives empty, log warnings without goals or steps). A `RouteStoring` protocol (in core or mac) for tests.
- `TaskRunner`: optional `routes`; match once after the first observation unless follow-up or `routeMemory` off; set `pastRoute` on every step's request; record element titles of label targets per step; in `finish`, on `.done`, not a follow-up, at least 2 clean steps: save; keep `lastMatched`/`lastSaved`, cleared per task.
- `VoicePipeline`: handle `.forgetRoutes`: drop `lastMatched`/`lastSaved` or all; rows `forgot that route` / `no route to forget` / `forgot all routes`. Wire the store in `AppDelegate`. CLI passes none.
- `TaskRunnerTests` with a fake store: done with 2 clean steps saves by name; stuck, follow-up, 1-step save nothing; a stored match reaches the step request.

## Task 5: docs
- `docs/voice-commands.md` two rows; `docs/tasks.md` paragraph; `docs/configuration.md` `routeMemory` row; `docs/privacy.md` Routes item (what is stored, mode 600, clear by "forget all routes" or deleting the file, `routeMemory: false`, follow-up and question interaction); README Privacy line. Spec `Status: Shipped` line is done at closeout (open-pr).
