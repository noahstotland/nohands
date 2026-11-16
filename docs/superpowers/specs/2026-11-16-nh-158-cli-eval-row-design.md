# NH-158: Add the eval row to the CLI docs table: Design

**Date:** 2026-11-16  **Ticket:** [NH-158](https://github.com/noahstotland/nohands/issues/158)
**Status:** Shipped
**Shipped:** in PR #174, as specified

## Intent

`docs/cli.md` lists every `nohands-cli` subcommand except `eval`. Checked against `Sources/nohands-cli/main.swift` on `main` at 6312115, `eval` is the only subcommand in the `switch` and the usage text with no row (`scenarios`, `pack` and `registry` already have theirs).

## Scope

One new row in the `docs/cli.md` table, right after `scenarios` (the order the usage text uses):

| Subcommand | Does |
|---|---|
| `eval <file> [--runs N]` | Dry run: sends each phrase in the fixture file (e.g. `scripts/intent-eval.json`) to the configured backend `N` times (default 1), prints `PASS` or `FAIL` with the time per call, then accuracy, median time (without the first 2 calls) and model. Executes nothing; spends API credit with the Claude backend. Exits 0 even when cases fail; 1 for a bad file or with the backend off |

Facts behind the row (from `main.swift` and `CLIHelpers.swift`): `--runs` takes an integer of at least 1, anything else prints the usage and exits 1; an unreadable or invalid file throws and exits 1; `loadResolver` exits 1 with `error: LLM off` when the backend is off; there is no start delay.

Non-goals: documenting the fixture format (out of scope per the ticket); changing `eval`'s behaviour or usage text.

## Calls I made

- Spelled out that `eval` exits 0 even when cases fail, since a reader might expect it to gate CI like `scenarios` does.
- Put the row after `scenarios`, matching the usage order, rather than next to `resolve`.
- Named `scripts/intent-eval.json` as the example file, since `docs/agents/project.md` points there.
- No plan: the ticket changes only markdown, so the build works from this spec.
