# NH-91 plan: model-written plans, run and checked in code

Spec: `docs/superpowers/specs/2026-11-08-nh-91-model-written-plans-design.md` (approved). Branch `feat/nh-91-youtube-latest-route`.

## File map

- Core `TaskPlan.swift`, `PlanGate.swift`: the plan model, its validation (spec § "Plans are untrusted") and the gate (4+ words, a media goal or known site).
- Core `PlanTargets.swift`: `click` prefers an exact title match and skips menu bar items; `click_first_item` picks the first content link not in a navigation stack by frame.
- Core `PlanEngine.swift`: compiles steps to `IntentStep`, `.finish` or `.handOver`. A missed check waits 1500 ms once, then hands over. Play is clicked at most once.
- Core `PlanQuestion` and `plan(goal:)` on both resolvers.
- Mac `TaskRunner`: gate, ask, plan branch (200-element limit).

## Build gate and measurement

- Real Chrome element lists are pinned as test data for the navigation-stack rule.
- Ten goals on the local model through `nohands-cli task`. Hard bar (user, 2026-11-09): "put on the latest outdoor boys video" must end playing, else stop with `BLOCKED:` and the numbers. No Claude key here, so Claude runs go in `Not proven`.
