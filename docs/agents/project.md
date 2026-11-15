# Project config (NoHands)

Repo-specific facts the agent-team skills read. `TODO(<owner>)` marks an undecided value; an agent that needs one must not guess (in team mode, stop with `BLOCKED:`). Scripts read the first backticked token in each Value cell: keep it, and put no extra backticks in notes.

## Identity

| Key | Value |
|---|---|
| Product name | NoHands, a macOS menu-bar app that controls the Mac by voice alone: on-device speech recognition, dictation, shortcuts, mouse, and natural-language commands resolved by Claude or a local Ollama model |
| Tracker (`linear`, `github` or `jira`) | `github` |
| Tracker scope (`<TEAM>`) | the GitHub repo `noahstotland/nohands` |
| Linear team name (Linear only) | none |
| Issue identifier prefix (`<PREFIX>`) | `NH` |
| Linear project (Linear only) | none |
| Approver | Noah Stotland (`noahstotland`). Approves specs and merges only |
| Approval risk tolerance (`strict`, `balanced` or `permissive`) | `permissive`. Approvals taken without asking: `strict` none, `balanced` Low risk, `permissive` Low and Medium. High always waits for you |
| No Hands (`off` or `on`) | `on`. Whether you may start a No Hands run: the Chief of Staff approves specs and merges itself, at any risk level, until the Backlog is empty or a cap below is hit. Reviews, CI and merge gates still run; changes to the files that decide approvals wait for you |
| No Hands ticket cap | `10`. Tickets one No Hands run may start |
| No Hands cost cap (USD) | `200`. API-equivalent spend of the run's tickets, from `agent_usage.py` |

### Choosing a tracker

A missing `Tracker` row or a `TODO(...)` value means `linear`. Operations and adapters: [trackers/README.md](trackers/README.md).

- `github`: no extra rows. Tickets are GitHub issues in the `Repo` below; the prefix is any short one (for example `GH`). `~/.collective-wisdom/scripts/gh.sh` does every call.
- `jira`: untested. Add the rows listed in [trackers/jira.md](trackers/jira.md) § project.md rows to the table above.

## Git and GitHub

| Key | Value |
|---|---|
| Branch pattern | `feat/nh-N-short-title` (`<prefix>` is the issue prefix in lower case) |
| Repo (`<owner>/<repo>`) | `noahstotland/nohands` (<https://github.com/noahstotland/nohands>) |
| Owner login (trusted review-comment author) | `noahstotland` |
| GitHub CLI | `~/.collective-wisdom/scripts/gh.sh` only, never bare `gh`. Setup: [github-auth.md](~/.collective-wisdom/docs/agents/github-auth.md) |
| Commits | Conventional: `feat:`, `fix:`, `docs:`, `infra:`, `chore:`; a scope in parentheses names the target (`fix(mac):`, `fix(core):`). Small, focused commits |

## Commands

| Key | Value |
|---|---|
| Test | `swift test` |
| Lint | none (no linter configured) |
| Typecheck | `swift build` (Swift 6 strict concurrency; a clean build is the typecheck) |
| Required CI checks | `none (no CI yet)` |
| Agent-team script tests | `python3 -I -m pytest -q scripts` (needs `pytest`, e.g. `uvx pytest -q scripts`) |
| Docs index listing | `python3 ~/.collective-wisdom/scripts/docs_index.py` (one table of every spec, plan and as-built under `docs/superpowers/`) |
| Release notes listing | `python3 ~/.collective-wisdom/scripts/release_notes.py` (merged-PR `## Release note` sections and `docs/superpowers/release-notes/*.md`, newest first) |
| Test database | none |
| Migration heads check | none |
| Migrations directory | none |

### Other commands

- Build and run: `scripts/bundle.sh && open build/NoHands.app` (needs Microphone and Accessibility permissions on first run; see `README.md`).
- Intent fixtures: `.build/debug/nohands-cli eval scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json`. Never edit fixture expectations to make a test pass; fix the prompt or the grammar.
- Local model setup: `scripts/setup-local-model.sh`.

## Repo invariants

Skills and the Chief of Staff restate these in every child task.

- The root checkout stays on `main`. Branch work happens in a worktree: `.worktrees/<short-name>/`, or the one T3 Code created under `~/.t3/worktrees/`.
- Never push to `main`; push only the ticket's own `feat/nh-N-*` branch.
- Exception: the publish step in `~/.collective-wisdom/scripts/merge_pr.py` writes `RELEASE_NOTES.md` on the `release-notes` branch through the GitHub API after a merge. No agent, skill or other script writes that branch, by push or by API.
- Never commit `.env`, API keys or tokens. The Anthropic key lives only in `~/.config/nohands/config.json` or the `ANTHROPIC_API_KEY` environment variable.
- All targets build in Swift 6 language mode with strict concurrency. Do not weaken it (no `@unchecked Sendable`, no `@preconcurrency` imports); fix the isolation.
- `NoHandsCore` has no AppKit, CoreGraphics event or network dependencies. Pure logic (grammar, mode machine, intent decoding, formatting) goes there with unit tests; macOS integration goes in `NoHandsMac`.
- Ordinary commands never touch the network. Speech recognition and the fast grammar stay on-device; only unmatched natural-language commands may call Claude or the local model, and the local model is only reached over `http` on loopback.
- A spoken "stop" is never merged into another utterance and always halts the running task.
- Tests that need the microphone, Accessibility or a running model are not unit tests. Keep `swift test` runnable with no permissions granted and no Ollama.
- Do not delete `~/.config/nohands/` or the downloaded speech and Ollama models when cleaning up.

## Areas and labels

- Area labels: `core` (`Sources/NoHandsCore`), `mac` (`Sources/NoHandsMac`, `Sources/NoHands`), `cli` (`Sources/nohands-cli`), `docs`. Type labels: `type:feature`, `type:improvement`, `type:bug`. Team labels `agent` and `agent-skip` are managed by the Chief of Staff and the approver.
- Areas (path boundaries per role): none; one implementer covers every target.

## Product rules

- Brand in the interface: NoHands.
- Speech and the fast grammar stay on-device; the model is optional and the app must keep working with it off ("LLM off").
- Every command phrase in the `README.md` voice command table keeps working. A new phrase is added to the table in the same PR.
- The HUD and menu-bar text stay short: one line, no jargon, and every failure names what the user can do next (grant Accessibility, start Ollama, download the model).
- Accessibility actions must be reversible by voice: anything that holds a state (hold click, dictation mode, sleep) has a spoken release.

## Security overlays

Extra security-review checks on top of OWASP and "no secrets in repo".

- Transcripts and typed text are private: logged with the unified log's private marker and never sent anywhere except the configured intent backend.
- The config file may hold an API key: it is read with a permissions warning and never written back with the key in plain text to a new location.
- The Ollama URL is validated to loopback over `http` only; any change to `ollamaURL` handling keeps that check.
- Model output is untrusted: actions from Claude or the local model go through the intent schema and the task guards before anything is typed, clicked or opened. No new action type bypasses the decoder or the guards.
- Synthesized keyboard and mouse events only act on the frontmost app the user targeted; never add a global key or mouse hook that captures input from other apps.

## Docs

| Key | Value |
|---|---|
| Specs / plans / as-built | `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/superpowers/as-built/` |
| Index | Generated by `python3 ~/.collective-wisdom/scripts/docs_index.py`; nothing to edit by hand. Layout: [`docs/superpowers/README.md`](../superpowers/README.md) |
| Release notes | A `## Release note` section in each PR body; older notes in `docs/superpowers/release-notes/`. Every merge publishes them all to `RELEASE_NOTES.md` on the `release-notes` branch (<https://github.com/noahstotland/nohands/blob/release-notes/RELEASE_NOTES.md>). Layout as above |

## Docs check

Read by the documenter subagent ([documenter.md](~/.collective-wisdom/docs/agents/documenter.md)).

- Living docs to search: `README.md`, `AGENTS.md`, `docs/agents/`, `.claude/skills/`, `docs/superpowers/specs/2026-11-04-nohands-design.md` (the architecture spec).
- Extra checks: the voice command and CLI subcommand tables in `README.md` when the diff touches `CommandGrammar.swift` or `Sources/nohands-cli/main.swift`; the Configuration section in `README.md` when it touches `AppConfig.swift`.

## Environments and deploy

No hosted environments. The app runs locally from `scripts/bundle.sh` and is distributed by hand (no release pipeline yet); Noah Stotland builds and installs it.

## Models

Defaults live in the `chief-of-staff` skill, section Models. They are defaults, not repo rules; change them by ticket and PR.
