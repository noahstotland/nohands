# NH-39: Measure the Claude model tiers on the intent fixtures — Design

**Date:** 2026-11-05  **Status:** Shipped  **Ticket:** [NH-39](https://github.com/noahstotland/nohands/issues/39)
**Shipped:** in PR #187, with differences: [as-built](../as-built/2026-11-23-nh-39-claude-tier-eval.md)

## Intent

Every request the grammar misses goes to `claude-opus-5-5` at `medium` effort, whether it is "full screen" or a
12-step web task. This change measures what the Haiku and Sonnet tiers get right on the intent fixtures and how
long each tier takes, records the numbers, and sets the defaults from them. If a faster tier is as accurate on
the first step of a request, it becomes an optional fast tier for that step only.

## Today

- `AppConfig.intentModel = "claude-opus-5-5"`, `intentEffort = "medium"` (`Sources/NoHandsCore/AppConfig.swift`).
  `ClaudeIntentResolver.resolve` builds every request with that one pair.
- `nohands-cli eval <file> [--runs N]` (`Sources/nohands-cli/main.swift`) resolves each case as
  `StepRequest(oneShot:)`, which is step 1 with no history. It already prints `PASS 812ms  <say>` per call and
  one line `accuracy=…% median=…ms (excluding first 2 calls) model=…`. It has no p95, the summary math is inline
  and untested, and the only way to pick a model or effort is to edit `~/.config/nohands/config.json`.
- Fixtures: `scripts/intent-eval.json` (40 cases) and `scripts/intent-eval-disfluent.json` (14 cases). Every
  case is a single first-step request. Nothing in them scores step 2 onward of a multi-step task.
- No prompt caching on the Claude path yet (#37 adds it). Prompt caches are per model.

## Approaches

1. **Measure, then set one (model, effort) pair for everything.** Simple, but the fixtures only score step 1.
   Moving task steps 2+ to a cheaper tier on that evidence would be a guess.
2. **Measure, then add an optional fast tier for step 1 only, re-asked on the main tier when it says the
   request needs more steps.** The fixtures measure exactly the step the fast tier would serve. **Chosen**, with
   the fast tier off by default unless the numbers below say otherwise.
3. **Route by a heuristic** (transcript length, keywords) before calling any model. Rejected: guesswork the
   ticket asks us to replace, and it adds a rule nobody measured.

## Design

### 1. Eval summary (`NoHandsCore/IntentEval.swift`)

A pure, tested summary replaces the inline math:

```swift
public struct EvalSummary: Equatable, Sendable {
    public var passed: Int, total: Int
    public var p50Ms: Int, p95Ms: Int        // nearest-rank percentiles; 0 when there are no samples
    public init(results: [(passed: Bool, ms: Int)], dropFirst: Int = 0)
    public var line: String                  // "pass=52/54 (96%) p50=812ms p95=2140ms"
}
```

- Percentiles use nearest rank (`ceil(p × n)`-th smallest), so p95 of 3 samples is the largest.
- `dropFirst` drops the first N samples from the latency figures only (pass counts always use every call). The
  CLI passes 2 for the local backend (Ollama's cold load, as today) and 0 for Claude.
- An error counts as a fail, and its wall time counts in the latency figures.

### 2. Eval flags (`nohands-cli eval`)

`nohands-cli eval <file> [--runs N] [--model ID] [--effort LEVEL]`

- `--model` and `--effort` override `intentModel` and `intentEffort` for this run only; the config file is not
  touched. `--effort` must be one of `AppConfig.efforts`, else usage. Either flag with a non-Claude backend
  exits with `error: --model and --effort apply to the Claude backend`.
- Flags may come in any order after the file. Per-call lines stay as they are. The last line becomes
  `<summary.line> model=<id> effort=<level>` (effort omitted for the local backend).
- README has no `eval` row today; the CLI usage text (`nohands-cli` with no arguments) documents the flags.

### 3. The measurement

Run both fixture files with `--runs 3` for each of the six pairs: `claude-haiku-5-5`, `claude-sonnet-5-5` and
`claude-opus-5-5`, each at `low` and `medium`. That is 54 cases × 3 runs × 6 pairs = 972 API calls on the user's
key from `~/.config/nohands/config.json`. Run from one machine on one network, pairs back to back, and record
the date, machine and network in the note. If a tier rejects a field (effort or the JSON schema), record the
error as its result; do not change the request to make it fit.

The note `docs/superpowers/as-built/2026-11-05-nh-39-claude-tier-eval.md` holds one table per fixture file:
pair, pass rate, p50, p95, and the failing case texts. Fixture expectations are never edited.

### 4. The decision rule (fixed before the run)

A pair **qualifies** when it passes every case on all 3 runs of both files (100%).

- **Main tier (`intentModel`, `intentEffort`) does not change.** It also serves steps 2+ of tasks, which the
  fixtures don't score. If `claude-opus-5-5`/`medium` itself misses 100%, the note says so and lists the cases;
  defaults stay and a follow-up ticket is proposed in the note (prompt work is out of scope here).
- **Fast tier.** Among qualifying pairs other than opus/medium, take the one with the lowest p50 across both
  files (ties: lower p95, then the larger model). If its p50 is at least 25% below opus/medium's, it becomes
  the default fast tier. Otherwise there is no fast tier, the note says why, and step 6 below is skipped.

### 5. Fast tier config (only if step 4 picks one)

- `AppConfig.intentFastModel: String = "<picked model>"` and `intentFastEffort: String = "<picked effort>"`,
  decoded with `decodeIfPresent ?? default`. An empty `intentFastModel` turns the fast tier off. An invalid
  `intentFastEffort` falls back to its default, like `intentEffort`.
- Pure rule in Core (`IntentTier.swift`):
  - `IntentTier.forRequest(_ r: StepRequest, config:) -> (model: String, effort: String, isFast: Bool)`:
    the fast pair when the fast tier is on and `r.step == 1 && r.history.isEmpty`, else the main pair.
  - `IntentTier.needsMainTier(_ status: StepStatus) -> Bool`: true for `continue` and `stuck`.
- `ClaudeIntentResolver.resolve`: ask the tier `forRequest` picks. If it was the fast tier and
  `needsMainTier(step.status)`, discard that answer (nothing it returned is executed) and ask the same request
  on the main tier. A fast-tier error or timeout also falls through to the main tier once, so the fast tier
  never makes a request fail that the main tier would have answered.
- The re-ask shares the step's deadline budget: the main-tier call gets what is left of `llmDeadlineMs`, with a
  floor of 2 s. (A full second deadline would let one spoken request wait 24 s.)
- `nohands-cli eval` keeps scoring one pair per run (it passes `--model`/`--effort` straight through), so the
  table stays comparable.

### 6. Docs

- README § Configuration: the measured numbers next to `intentModel`/`intentEffort`, and the fast-tier keys if
  added. The "Claude vs. the local model" paragraph gets the Claude p50/p95 for the default pair.
- The note states the cost of two models: with #37's caching, each model keeps its own cache of the ~same
  system prompt, so the main model's cache is warmed only by task steps 2+ and re-asks, and goes cold more
  often; a request the fast tier hands up pays the fast call's latency plus a main-tier call that may miss the
  cache. Without #37 (today) there is no cache to lose, only the extra call.

## Tests

- `EvalSummary`: one table test covering empty input, all pass, mixed with errors, nearest-rank p50/p95 on
  odd and even counts, and `dropFirst` affecting latency but not the pass count.
- If the fast tier is added: one table test for `IntentTier.forRequest` (tier off, step 1 no history, step 1
  with history, step 2) and `needsMainTier` over every `StepStatus`; `AppConfigTests` rows for the two new keys
  (defaults, parse, empty model, bad effort). One resolver test with a stub session: fast answers `continue`,
  the main tier is asked and its answer is returned.
- Manual (listed in the PR): the six eval runs; one spoken "full screen" and one multi-step task with the fast
  tier on.

## Acceptance

- The note has pass rate, p50 and p95 for every (model, effort) pair on both files.
- Both fixture files are at 100% on the chosen default (or the note shows opus/medium itself is not, and
  nothing changed).
- `swift test` green; `EvalSummary` is a pure function with a test.

## Out of scope

- Local model tuning (#8), prompt or schema changes, prompt caching (#37).
- Changing the main tier for task steps 2+.

## Calls I made

- **The build spends API money on the user's key**: 972 calls across six pairs, about two thirds of them on
  Sonnet and Opus. The ticket asks for exactly this run; nothing is added on top.
- **The main tier never changes from these numbers**, even if Haiku passes everything, because the fixtures
  only score step 1 and the main tier also runs multi-step tasks. Any faster pair that qualifies can only become
  the step-1 fast tier.
- **Fast tier threshold: at least 25% lower p50 than opus/medium.** Below that, a second model's cache and
  re-ask costs aren't worth it.
- **A fast-tier error or timeout falls back to the main tier once**, and the re-ask shares the step deadline
  (2 s floor) instead of getting a fresh one.
- **`--model`/`--effort` flags on `eval`** so the run never rewrites the user's config file.
- **Latency for Claude counts every call**; the "skip the first 2 calls" warm-up stays for the local backend only.
- **Nearest-rank percentiles**, so p95 of a small sample is its slowest call rather than an interpolation.
- **If opus/medium misses 100%**, defaults stay, the note lists the failing cases and proposes a follow-up
  ticket rather than touching the prompt.
