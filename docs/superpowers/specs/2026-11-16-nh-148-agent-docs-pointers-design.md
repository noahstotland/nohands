# NH-148: Point the agent docs at docs/voice-commands.md and docs/configuration.md: Design

**Date:** 2026-11-16  **Ticket:** [NH-148](https://github.com/noahstotland/nohands/issues/148)
**Status:** Shipped
**Shipped:** in PR #178, with a small difference: the Extra checks trigger files are paired with their own doc (see PR)

## Intent

#119 moved the voice command table to `docs/voice-commands.md`, configuration to `docs/configuration.md` and the CLI table to `docs/cli.md`. The agent docs still send readers to the README for them. This ticket changes only those pointers: no rule, invariant or gate changes.

Checked on `main` at 9f78aae. `.claude/skills/` does not exist in this repo, so there is nothing to fix there.

## Scope

Three lines, pointer text only:

| File | Today | After |
|---|---|---|
| `docs/agents/project.md` § Product rules | "Every command phrase in the `README.md` voice command table keeps working." | "Every command phrase in the voice command table in `docs/voice-commands.md` keeps working." (rest of the line unchanged) |
| `docs/agents/project.md` § Docs check, Extra checks | "the voice command and CLI subcommand tables in `README.md` when the diff touches ...; the Configuration section in `README.md` when it touches `AppConfig.swift`." | "the voice command table in `docs/voice-commands.md` and the CLI subcommand table in `docs/cli.md` when the diff touches ...; `docs/configuration.md` when it touches `AppConfig.swift`." (same trigger files) |
| `AGENTS.md` § Workflow | "Key setup: `README.md` § Configuration." | "Key setup: `docs/configuration.md`." |

Each new target was checked: `docs/voice-commands.md` holds the `Say | Does` table, `docs/cli.md` the `Subcommand | Does` table, and `docs/configuration.md` the config key table with `anthropicAPIKey`.

Kept as is:

- `README.md` stays in the § Docs check living-docs list (the ticket asks for that).
- `docs/agents/project.md` § Other commands, "see `README.md`" for first-run permissions: the README's "Install and first run" section still holds them, so the pointer is not stale.
- The `trackers/README.md` and `docs/superpowers/README.md` links and the `~/.collective-wisdom/docs/agents/README.md` reference: these are other READMEs, not the moved content.

## Non-goals

- Any rule, invariant, gate or approval wording in `AGENTS.md` or `docs/agents/project.md`.
- Adding the new `docs/*.md` files to the living-docs list (see Calls I made).
- Edits to the README or the `docs/` pages themselves.

## Verification

- `grep -n "README" AGENTS.md docs/agents/project.md` shows no pointer to the voice command table, CLI table or Configuration section.
- `git diff --stat` touches only `AGENTS.md`, `docs/agents/project.md` and this spec (plus closeout).
- Markdown only, so no plan and no `swift test` change; `swift test` still runs before the PR per `AGENTS.md`.

## Calls I made

- Did not add `docs/voice-commands.md`, `docs/configuration.md` and `docs/cli.md` to the living-docs list. The Extra checks row already sends the documenter to them when the code they describe changes, and adding them would widen the docs check, which is a gate change the ticket rules out. Easy to do in a follow-up if wanted.
- Pointed key setup at `docs/configuration.md` as the ticket says, though the README's "Claude or a local model" section also covers the menu's **Set Claude API key…** item. `docs/configuration.md` has the `anthropicAPIKey` key and the local-model section, so it is the fuller target.
- Left the "see `README.md`" permissions pointer in § Other commands, since that content did not move.
- Kept the Extra checks trigger files (`CommandGrammar.swift`, `Sources/nohands-cli/main.swift`, `AppConfig.swift`) exactly as they are.
- No plan: the ticket changes only markdown, so the build works from this spec.
