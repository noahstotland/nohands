# NH-99: Cut the repo docs to a fraction of their length

**Date:** 2026-11-15
**Status:** Draft
**Ticket:** [NH-99](https://github.com/noahstotland/nohands/issues/99)

## Goal

The docs say every fact once, in plain sentences, and run well under half their current length. No rule, command, invariant, config key, CLI subcommand or voice phrase is lost.

## Today

Word counts (`wc -w`, 2026-11-15, origin/main at 505294c). These have grown since the ticket was written:

| File or set | Words |
|---|---|
| `README.md` | 8,720 |
| `AGENTS.md` | 693 |
| `docs/agents/project.md` | 1,377 |
| `docs/superpowers/` (110 specs, plans and as-built notes) | about 118,200 |

The largest under `docs/superpowers/` are the plans `2026-11-04-nohands-voice-control.md` (7,317) and `2026-11-04-agent-desktop-harness.md` (6,082), and the specs for NH-91 (3,994), the agent-desktop harness (3,349), NH-41 (2,998) and NH-90 (2,770). About 40 files are over 1,250 words.

## Design

### Targets

| File or set | Target |
|---|---|
| `README.md` | 3,500 words or fewer (40% of today) |
| `AGENTS.md` | 450 or fewer |
| `docs/agents/project.md` | 1,000 or fewer |
| `docs/superpowers/` total | 50,000 or fewer (about 42%) |

A target is a ceiling. Hitting it never justifies dropping a fact. If a file can't reach its target without losing a fact, keep the fact and say so in the PR.

### What stays

- **Facts.** Every rule, command, invariant, config key and its default and range, CLI subcommand and flag, voice phrase, number (timeouts, thresholds, measured latencies), file path, and every decision with its reason in one sentence.
- **Structure scripts read.** Each doc's first `# ` heading, unchanged. The `**Date:**`, `**Status:**`, `**Ticket:**`, `**Shipped:**` and `**Spec:**` header lines, unchanged, with their as-built links. The heading layout `docs/superpowers/README.md` § Closeout describes (an as-built keeps `## Differs from the spec`). In `project.md`, every table row, its key, and the first backticked token of its Value cell, unchanged. Notes in those cells get no extra backticks.
- **README sections the documenter checks.** The voice command table, including the per-app commands table, every phrase kept word for word. The CLI subcommand table and the `## Configuration` section stay in `README.md` with their current headings.
- **Links.** Every link that resolves today still resolves.

### What goes

- Repeated facts. Each fact is said once, and the other place points to it.
- Narration: "we", "this section explains", step-by-step transcripts, task lists with checkboxes and per-step code blocks in shipped plans, test output pasted in.
- Rejected-option essays, cut to one line per option with its reason.
- History the code or git log already holds: "previously", "originally", "in PR #N we changed".
- Em dashes, filler and hedging (`human-writing` skill).

### Per file

- **`AGENTS.md` and `project.md`.** Where they overlap (secrets, commits, commands, invariants, the product summary), `project.md` keeps the fact and `AGENTS.md` points to it. `AGENTS.md` keeps what only it says: required reading, the GitHub wrapper rule, the workflow, the Testing rules, and the Agent config section.
- **`README.md`.** Tightened in place, section by section, same headings and order. The heaviest cuts go to Multi-step tasks (and the agent-desktop harness), Configuration prose (the key table stays), Run it, and Privacy.
- **`docs/superpowers/`.** Every file over 800 words is rewritten, largest first. A file under 800 words gets only a light pass for em dashes and repeats. A shipped plan keeps its goal, its file map and the decisions and numbers a reader needs to see how the thing works; the task-by-task steps and code go, since the code is in the repo. A spec keeps goal, behaviour, constraints, decisions with reasons, numbers and its `## Calls I made`. An as-built keeps every difference bullet.
- **`docs/superpowers/README.md`** gets the same pass, and its Closeout, Release notes and Merge gate rules stay word for word in meaning.

### How it is checked

A throwaway check script in the scratchpad (not committed) runs before and after:

1. Word counts per file, written into the PR as a before and after table.
2. Every voice phrase in the README tables, every CLI subcommand, every config key, and every `project.md` table key and first Value-cell token from before is present after.
3. Every backticked token in `README.md`, `AGENTS.md` and `project.md` before still appears somewhere in the docs after. Any that don't are listed and each is either restored or shown to be a duplicate.
4. `python3 ~/.collective-wisdom/scripts/docs_index.py` lists the same files with the same titles before and after.
5. `git diff --stat origin/main` shows only `.md` files, and no change to `scripts/intent-eval*.json` or any source file.
6. `swift test` passes.

Reviewers get the before and after files; the code review checks a sample of the rewritten superpowers docs against their originals for a lost fact.

## Leaves out

- The structural README rewrite in NH-119 (moving reference tables to a `docs/` page, a newcomer-first layout, the Contributing section, `CONTRIBUTING.md`).
- The shared collective-wisdom docs, `scripts/intent-eval*.json`, any source file.
- Changing any rule, behaviour or default; deleting or renaming doc files; changing the specs, plans and as-built layout.
- `CONTRIBUTING.md`, `SECURITY.md`, `THIRD_PARTY_LICENSES.md`, `.github/` templates, `Tests/Fixtures/audio/README.md`.

## Calls I made

- **`AGENTS.md` and `docs/agents/project.md` are on the hands path,** so this spec and its merge need the user's own approval, not an auto-approval. The ticket asks for both files, so they stay in scope.
- **The README is tightened in place, not restructured.** NH-119 (open, Todo) restructures it and moves the reference tables out. Doing both here would collide with it. Whichever lands second rebases onto the other; NH-119 should start from this shorter text.
- **Targets use today's counts,** which are larger than the ticket's (README 8,720 not 6,320; `docs/superpowers/` about 118,000 not 69,000).
- **Numeric targets**: README 40%, `AGENTS.md` 65%, `project.md` 73%, `docs/superpowers/` 42%. `project.md` cuts less because its table keys and values must stay.
- **The 800-word line** for a full rewrite under `docs/superpowers/`. Smaller files get a light pass only, which keeps the diff reviewable.
- **Shipped plans lose their step-by-step tasks and code blocks** and keep goal, file map, decisions and numbers. The ticket allows this ("drop task-by-task narration"); it is the largest single cut.
- **No plan file.** The ticket changes only markdown, so the build goes from this spec (`kickoff-feature` step 6).
- **The fact check script stays out of the repo,** since a new file under `scripts/` would be on the approval path and the ticket adds no code.
- **One PR, about 115 files.** The ticket asks for one; past 100 files a No Hands merge waits for the user anyway.
- **This spec's status** is Draft until approved, then Shipped at closeout.
