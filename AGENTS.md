# NoHands: Agent Instructions

All agents working on this repo must follow these rules. Repo-specific facts (product, tracker, commands, commits, secrets, invariants) live in `docs/agents/project.md`.

## Product

**NoHands** controls a Mac by voice alone (summary: `docs/agents/project.md`). Stack: Swift 6 (strict concurrency), SwiftPM, macOS 14+, AppKit and Accessibility APIs, FluidAudio (Silero VAD and Parakeet ASR on-device), the Claude API and Ollama for intent resolution. Targets: `NoHandsCore` (pure logic, unit tested), `NoHandsMac` (macOS integration), `NoHands` (the app), `nohands-cli` (dev tool). Update this section and `docs/agents/project.md` as it changes.

## Required reading

1. `docs/agents/project.md`
2. `~/.collective-wisdom/docs/agents/org-chart.md`: who is on the agent team and what each role may do
3. Your role file in `~/.collective-wisdom/docs/agents/` (see `~/.collective-wisdom/docs/agents/README.md`)
4. `~/.collective-wisdom/docs/agents/security-review.md`: OWASP-aligned PR security review before merge (ship loop phase 4)

## GitHub

- Use `~/.collective-wisdom/scripts/gh.sh` for all `gh` commands, never bare `gh`. If you must, prefix it: `env -u GITHUB_TOKEN -u GH_TOKEN gh ...`.
- Never export a limited PAT as `GITHUB_TOKEN` locally. It overrides `gh auth login` and causes `Resource not accessible by personal access token` on GraphQL.
- Full setup: `~/.collective-wisdom/docs/agents/github-auth.md`.

## Workflow

- Write or edit tickets with the `write-ticket` skill.
- **One ticket = one branch = one PR.** Link the ticket in the PR description. Do not expand scope beyond it.
- Move the ticket to **In Review** when the PR is open, **Done** when merged.
- Run the test command from `docs/agents/project.md` before opening a PR.
- Never commit `.env`, API keys or tokens. Key location and commit format: `docs/agents/project.md`. Key setup: `README.md` § Configuration.

## Testing

Write tests for behavior that would hurt users if it broke without anyone noticing. Skip the rest.

Test:

- Everything in `NoHandsCore`: command grammar, mode machine, intent decoding, dictation formatting, number words, label and grid mapping, task guards
- Safety rules: "stop" is never merged, the shortcut guard, the Ollama loopback-only URL check, model output rejected by the schema
- Config parsing and defaults, including invalid JSON and missing keys
- Error paths that must not take down the pipeline or a task (model timeout, denied permission, stale job)
- The intent fixtures in `scripts/intent-eval*.json` keep passing; never edit expectations to make them pass

Don't test:

- Menu-bar and HUD layout or copy
- Anything that needs the microphone, Accessibility, a real app or a running model (manual checks, listed in the PR)
- Constants and registries
- Framework or library behavior (AppKit, FluidAudio)

How: one table-driven test per rule, not per edge case. A test must be able to fail for a real bug; don't restate the implementation. In review, a fix gets a new test only when it fixes a real bug. Test lines should not exceed the feature code lines in the PR.

## Agent config

This file holds the shared instructions for every agent: Cursor, Claude Code, and T3 Code threads on either. `CLAUDE.md` imports it (`@AGENTS.md`).

- The machine install links the team's skills into `~/.claude/skills` (Claude Code), `~/.agents/skills` (Codex) and `~/.cursor/skills` (Cursor), and its subagents into `~/.claude/agents`. An app may hold its own skills in `.claude/skills/`.
- Each subagent points to a role file in `~/.collective-wisdom/docs/agents/`, which holds the real brief. On hosts that don't load that format, start a general subagent with the role file as its prompt.
- The team is installed once per machine from the collective-wisdom clone with `install.sh`; update it by checking out a newer release there and rerunning `./install.sh`. Only `docs/agents/project.md` lives in this repo; change shared files in collective-wisdom.
- Always-on project rules go in this file, not in `.cursor/rules/`.
