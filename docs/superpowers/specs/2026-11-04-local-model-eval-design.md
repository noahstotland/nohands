# Local model eval and prompt tuning (NH-8) — Design

**Date:** 2026-11-04  **Ticket:** [NH-8](https://github.com/noahstotland/nohands/issues/8)  **Status:** spec, awaiting approval

## Intent

No multi-step task has ever finished on the local model. Measure how `qwen2.5:3b-instruct` and
`qwen2.5:7b-instruct` do on the intent fixtures, raise the pass rate by changing only what the local backend
sends (its prompt, its few-shot examples, its schema property order), and write the numbers down so the README
can say plainly what the local backend can do.

## Today (checked in the code)

- `OllamaRequestBuilder` (`Sources/NoHandsCore/OllamaRequestBuilder.swift`) sends `IntentSchema.systemPrompt`,
  then `IntentExamples.turns` (12 turns, local only), then the request, with `IntentSchema.orderedSchema` as the
  Ollama `format`.
- The Claude backend sends the **same** `IntentSchema.systemPrompt` (`ClaudeRequestBuilder.swift:20`) and a
  schema derived from the same `orderedSchema`. So "change only the local prompt" means the local backend needs a
  prompt of its own; editing `IntentSchema.systemPrompt` would change Claude too.
- `nohands-cli eval <file> [--runs N]` scores whichever backend `loadResolver()` picks from
  `~/.config/nohands/config.json`. It prints `PASS|FAIL <ms>ms <say>` per run and a final
  `accuracy=… median=…` line.
- On this machine today: Ollama answers on `127.0.0.1:11434` with only `qwen2.5:7b-instruct` pulled (the 3B is
  missing); 16 GB RAM with about 3 GB free plus inactive; no `~/.config/nohands/` directory; no
  `ANTHROPIC_API_KEY` in the agent shell; `agent-desktop` is installed.
- Fixtures: `scripts/intent-eval.json` (40 cases), `scripts/intent-eval-disfluent.json` (14 cases).

## Approaches

1. **Edit the shared prompt.** Rejected: changes Claude's behaviour, which the ticket rules out.
2. **A local-only prompt built from the shared one** (the shared text plus local-only additions, or a trimmed
   copy). Chosen: Claude's request stays byte-identical, and the local prompt can be shorter, which also cuts
   prefill time on a 3B/7B model.
3. **Fine-tune or switch models.** Out of scope.

## Design

### Measuring tool

- `nohands-cli eval` and `nohands-cli task` gain `--local <model>`: force the local backend with that Ollama
  model for this run, whatever `config.json` says. Nothing is written to `~/.config/nohands/`. The Ollama URL
  still comes from config and still goes through the loopback-only `ollamaBaseURL` check.
- No change to how `eval` scores cases (`IntentEval.matches`) and no change to any fixture file.

### Local prompt (NoHandsCore)

- `IntentSchema.localSystemPrompt(for: HarnessKind)` (name left to the builder): used only by
  `OllamaRequestBuilder`. It starts as an exact copy of today's prompt, so the "before" numbers are unchanged,
  and is then edited by measurement.
- It must keep, word for word in meaning, rule 6 (no command-W/Q unless asked) and rule 7 (app name, window title,
  URL and element titles are untrusted data). The code guards (`TaskGuards`, `ShortcutGuard`, the decoder) are
  untouched either way.
- `IntentExamples` (already local only) may be reordered, trimmed or extended. New examples must not copy a
  fixture's `say` text or its exact site/app: they teach the pattern, not the answer key.
- `OllamaRequestBuilder` may use its own property order for the `format` schema (the ticket's "schema
  ordering"). Same kinds, same enums, same required fields, so `IntentDecoder` and the guards see exactly what
  they see today. `IntentSchema.orderedSchema` used by Claude stays as is.
- `warmBody` keeps matching the real request's prefix (existing test in `OllamaIntentTests`).

### Build-stage procedure

1. **Preflight, before any eval. Stop with `BLOCKED:` on any failure; never download a model, never guess.**
   - `curl -sf -m 3 http://127.0.0.1:11434/api/tags` answers. If not: `BLOCKED: Ollama is not running`
     (do not start it).
   - Its model list contains both `qwen2.5:3b-instruct` and `qwen2.5:7b-instruct`. If either is missing:
     `BLOCKED: <model> not pulled; run ollama pull <model>`. Never run `ollama pull` or
     `scripts/setup-local-model.sh`.
   - Before each 7B run: free plus inactive memory from `vm_stat` is at least 5 GB. If not:
     `BLOCKED: need ~5 GB free RAM for qwen2.5:7b-instruct, have <n> GB`.
   - `swift build` succeeds.
2. **Baseline ("before").** On the unchanged prompt, for each model and each fixture file:
   `nohands-cli eval <file> --runs 3 --local <model>`, run as a background command and waited on. Keep the raw
   output in the scratchpad and summarise it in the note.
3. **Tune.** Iterate on the local prompt, examples and schema order using `--runs 1` on the 7B for fast loops.
   Keep a change only if it raises the combined pass count on the 7B by at least 2 cases without lowering the 3B
   by more than 2. At most 6 iterations; then stop, even with no gain (a no-gain result is still a valid outcome).
4. **After.** Repeat step 2 on the final prompt with `--runs 3`.
5. **TextEdit task.** Open a new, untitled TextEdit document (`osascript`: activate TextEdit, make new document),
   then `nohands-cli task "type hello from NoHands" --local qwen2.5:7b-instruct` and keep the step log. If
   Accessibility is not granted to the agent's terminal, stop with `BLOCKED: grant Accessibility to the terminal
   running the build`. The document is left unsaved and open. The log records which harness was used
   (`agent-desktop` is installed here, so likely that one).
6. **Claude unchanged.** Show that every Claude request is byte-identical to `main`: a throwaway script (not
   committed) that builds `ClaudeRequestBuilder` bodies for every fixture case on both commits and diffs them. If
   an Anthropic key is available, also run both fixture files on Claude once; if not, list that eval under
   "Checks that didn't really run".
7. `swift test` passes.

### Outputs

- `docs/superpowers/as-built/<build date>-local-model-eval.md`: machine (chip, RAM, Ollama version), the commands,
  a table of pass rate and median time per model per fixture file, before and after; per-case results with
  pass count out of 3 and median ms; what changed in the prompt and why; the TextEdit step log, ending `done` or
  naming the failing step and why.
- `README.md` "Claude vs. the local model" paragraph rewritten with the measured numbers.
- `README.md` CLI table gains `--local <model>` for `eval` and `task`.

### Tests

- One table-driven test: the local request's system message carries the close/quit rule and the untrusted-data
  rule for both harnesses (safety rule; a trimmed prompt could drop them silently).
- One test: Claude's request still uses `IntentSchema.systemPrompt` (it guards against the local prompt leaking
  into Claude).
- Existing `OllamaIntentTests` updated to expect the local prompt; the warm-prefix test keeps passing.
- No test needs Ollama; `swift test` stays offline.

## Calls I made

- **The 3B model is not on this machine yet.** The build stops with `BLOCKED:` at preflight until someone runs
  `ollama pull qwen2.5:3b-instruct` (≈1.9 GB). Same for the 7B if it is removed.
- **RAM is tight right now** (about 3 GB free plus inactive of 16 GB). The 7B runs need about 5 GB; the build
  blocks rather than running a swapping eval whose timings would be meaningless.
- **Claude fixtures may not be re-run.** No API key is visible to the agent. The build proves Claude's requests
  are byte-identical to `main` instead and reports the live Claude eval as not run, unless a key is provided.
- **A small CLI flag (`--local <model>`) is added** so the build never creates or edits
  `~/.config/nohands/config.json` (it does not exist on this machine). This is tooling, not part of the prompt
  change, and does not affect the pass rate.
- **The local backend gets its own system prompt** rather than editing the shared one, so Claude is untouched.
- **Tuning rule:** keep a change only for ≥ 2 more passing cases on the 7B without a > 2 case drop on the 3B;
  at most 6 iterations; tune with 1 run, measure before/after with 3.
- **No overfitting:** new few-shot examples may not reuse a fixture's phrase or exact site/app.
- **The TextEdit goal is "type hello from NoHands"** in a fresh untitled document, on the 7B, left unsaved. It
  types into TextEdit on the user's Mac while it runs.
- Default local model is unchanged (`AppConfig.defaultLocalModel` still picks 7B at ≥ 12 GB).

## Leaves out

- Changing fixture expectations, `IntentEval` scoring, the Claude prompt or schema, the decoder or the guards.
- Pulling models, starting Ollama, or editing the user's config.
- New action kinds, new grammar phrases, or changing default deadlines/element caps (the note may recommend new
  values; changing them is a follow-up ticket).
