# NH-91 plan: model-written plans, run and checked in code

Spec: `docs/superpowers/specs/2026-11-08-nh-91-model-written-plans-design.md` (approved). Build on this branch,
`feat/nh-91-youtube-latest-route`. Test command: `swift test`. Typecheck: `swift build`. Tests per `AGENTS.md` § Testing:
one table-driven test per rule, none that need a microphone, Accessibility or a model.

## Task 0: build gate (done by the parent)

Real lists were captured in Chrome on 2026-11-09 and are in
`/private/tmp/claude-501/-Users-noahstotland--t3-worktrees-nohands-t3-2a752e97/4181a9c4-9ff2-4b8e-b5f0-405dc4860bf7/scratchpad/caps/`:
`p1-native.txt` (YouTube Veritasium Videos tab), `p3-native.txt` (Google results for "sourdough starter"). Format is
`n role (x,y wxh) title`. Pin trimmed copies of the rows that matter as test data (keep the sidebar rows and the
first video cards, so the stack test is exercised by real geometry). Finding recorded in the spec (content-link rule
uses a navigation-stack test on frames).

## Task 1: plan model, gate, text matching (Core)

Files: `Sources/NoHandsCore/TaskPlan.swift`, `PlanGate.swift`, `Tests/NoHandsCoreTests/TaskPlanTests.swift`.

- `TaskPlan` with steps (`intent`, `do`, `url`/`text`/`after`, `expect`), decoding from the JSON in the spec,
  `{"plan":null}` / empty = no plan, unknown step or check kind rejects the whole plan.
- `TaskPlan.validated(goal:)`: every rule in spec § "Plans are untrusted" (2 to 8 steps, URLs through
  `WebAddress.url(for:)`, `.example` hosts rejected, 80-char text, sanitized intents, one check tied to a distinctive
  goal word, a playback goal (`MediaSignal.wantsPlayback`) must end with `wait_for_media`).
- `PlanText.matches(_:in:)`: lower-case, fold accents, letters and digits only, spaces removed, substring.
- `PlanGate.mayPlan(goal:)` per spec § The gate (4+ words; `MediaGoal.matches` or a `WebAddress.knownSites` key or a
  domain-looking word; no browser name; none of `this`, `current`, `here`).
- Tests (table-driven): gate pass/reject; each validation rejection; text matching hit and miss; decoding of `null`,
  unknown kinds, non-JSON.

## Task 2: element picks (Core)

File: `Sources/NoHandsCore/PlanTargets.swift`, tests `PlanTargetsTests.swift`.

- `click`: first element whose title matches `text`, exact match preferred over partial; skip `AXMenuBarItem` roles
  (menu bar items are never plan targets).
- `click_first_item(after:)`: content-link rule from the spec (link role, not `offscreen`, 3+ words, not in a navigation
  stack by frame; elements after the one matching `after` when given). Takes `[ObservedElement]` plus
  `[Int: CGRect]` frames; no frames means no pick (hand over).
- Tests: the pinned real rows (YouTube: picks the first video card, not `Jef. New content available.`; Google: picks the
  first result), exact over partial, `after` anchor, no frames, no content link.

## Task 3: the engine (Core)

File: `Sources/NoHandsCore/PlanEngine.swift`, tests `PlanEngineTests.swift`.

- `PlanMove = .step(IntentStep) | .finish(String) | .handOver(String)`; `PlanEngine.next(observation, frames:)`.
- Step compile table from the spec; one extra `wait 1500` look on a missed check or missing target, then hand over;
  Play control clicked at most once; fixed hand-over reasons naming step number and check kind, none starting with
  `no element` or `element changed`.
- Tests: for each step type, the step produced; check hit moves on; check miss waits once then hands over; `.finish`
  after the last check; Play clicked once.

## Task 4: planning question and resolvers (Core + Mac)

- `PlanQuestion` in Core: system prompt, examples (invented `.example` sites; one `null` for a no-plan goal, one `null`
  for a Mac-app goal), `ClaudeRequestBuilder.planBody(goal:)`, `OllamaRequestBuilder.planBody(goal:)` (same `model`,
  `num_ctx`, `keep_alive` as a task step), response decoding to `TaskPlan?`.
- `IntentResolving.plan(goal:) async throws -> TaskPlan?` with a default returning nil; implement in
  `ClaudeIntentResolver` and `OllamaIntentResolver` reusing the existing send/deadline/status code.
- Tests: request body shape (Ollama options equal a task step's), decoding.

## Task 5: TaskRunner integration (Mac)

- `ScreenObserver.observe(... limit: Int? = nil)`; plan active uses 200.
- `TaskRunner.run` per spec § Changes in `TaskRunner`: gate, ask under `runCancellable`, plan branch takes the step
  from the engine, vision block and `while true` stay whole in the `else`, last-History-failure ends the plan, hand-over
  puts the reason on the last History record and cuts elements back to the normal cap.
  Rebase note: NH-90 and NH-41 are merged; keep `TypedAddressGuard.rewrite`, `ElementNames.bind` and the guards below the
  branch unchanged so plan steps pass through them.
- Tests in `TaskRunnerTests` with the fake resolver/executor: valid plan runs with no `resolve` call and ends `done`;
  failed check hands over with History filled; executor failure hands over; stop mid-plan ends `stopped`; `plan` error
  runs the normal loop; a goal failing the gate never calls `plan`.
- Fakes: extend `FakeResolver` (private in `TaskRunnerTests`) with a scripted `plan` result and call counter.

## Task 6: docs

README § Multi-step tasks paragraph and the privacy clause (spec § Docs). Run
`python3 ~/.collective-wisdom/scripts/compact_check.py` at the end.

## Task 7: measurement (the parent, live)

The 10 goals in the spec on the local model through `nohands-cli task`, table into the PR. No `ANTHROPIC_API_KEY` or
config key on this Mac, so Claude runs go in `Not proven`. Hard bar (user, 2026-11-09): "put on the latest outdoor boys
video" must end playing on the local model, else stop with `BLOCKED:` and the numbers.
