# NH-119: Rewrite the README to be short and readable, and refresh the contributing guide

**Date:** 2026-11-15
**Status:** Shipped
**Shipped:** in PR #139, as specified
**Ticket:** [NH-119](https://github.com/noahstotland/nohands/issues/119)

## Goal

A first-time reader goes from the top of `README.md` to a built, running app and a first voice command without scrolling past a reference table. The README is a short front page. The reference material moves, whole, to pages under `docs/` that the README links to. `CONTRIBUTING.md` matches the repo today.

## Today

Counts are from `wc` on origin/main at e78498a, after NH-99 merged. The README is 314 lines and 5,692 words, not the ticket's 278 lines and 6,300 words. NH-99 tightened it in place and kept every heading.

| README section | Holds |
|---|---|
| How it works, Requirements, Build | The pipeline diagram, the requirements, `swift build` and `swift test` |
| Run it | The prompt board, status bar, corner panel, recent commands and View Logs, the first-run permissions, ad-hoc signing, Start at Login, log lines, the Claude API key |
| Local model | `scripts/setup-local-model.sh`, the default model by RAM, `intentBackend`, the Model menu item, the server keys, the error rows |
| Voice commands | The voice command table (49 rows), the per-app commands table (Terminal), dictation notes, how text editing works |
| CLI tools | 22 `nohands-cli` subcommands |
| Configuration | 25 keys with defaults and ranges, and notes on the key, the Claude menu line, the session total, echo cancellation, the attention word, task-loop keys, pausing mid-command, effort |
| Multi-step tasks, agent-desktop harness | Task-loop internals, guards, vision fallback, pop-ups, stopping, the harness and its 6 keys, Claude vs. the local model |
| Privacy, Layout, Design, License | Nine privacy bullets, the source layout, design links, licences |

Other files point into the README by section:

- `AGENTS.md`: "Key setup: `README.md` § Configuration".
- `SECURITY.md`: "the Privacy section of the README".
- `THIRD_PARTY_LICENSES.md`: "see Configuration in README.md".
- `docs/agents/project.md`: the Product rule ("Every command phrase in the `README.md` voice command table keeps working"), the Docs check extra checks (the voice command and CLI tables and the Configuration section in `README.md`), and "see `README.md`" for first-run permissions.
- `CONTRIBUTING.md`: "Add a line to the README voice command table".

The status line ("work in progress, not yet verified on real hardware against real apps") is stale. The README itself quotes latency measured on an M1 Pro, and NH-38, NH-40 and NH-49 measured and scored tasks against real apps.

## Design

### New pages under `docs/`

Each section that moves keeps its text, tables and spec links. Only the heading levels change, plus an opening line saying what the page holds. Facts said twice inside the moved text are left alone. Cutting them is NH-99's job, and keeping them avoids losing a fact here.

| Page | Moved from the README |
|---|---|
| `docs/voice-commands.md` | The whole Voice commands section: the voice command table, the per-app commands table, the spec links, the dictation and attention-word notes, How text editing works |
| `docs/cli.md` | The whole CLI tools section and its table |
| `docs/configuration.md` | The whole Configuration section (the key table and every note), the Local model section, and the agent-desktop key table |
| `docs/using-nohands.md` | From Run it: the prompt board, status bar, corner panel, recent commands and View Logs, first-run detail, ad-hoc signing, Start at Login, logs |
| `docs/tasks.md` | The whole Multi-step tasks section and the agent-desktop harness section (its key table is linked from `docs/configuration.md`), and Claude vs. the local model |
| `docs/privacy.md` | The nine privacy bullets, word for word |

Each page links back to the README and to the others where the moved text pointed by anchor (for example `#agent-desktop-harness` and `#multi-step-tasks`). Links are rewritten so they resolve from `docs/`.

### The new README

About 1,500 words, roughly a quarter of today, in this order:

1. **Title and pitch.** `# NoHands` (the brand, not `nohands`), the icon and two sentences.
2. **Status.** One line: early software, run and measured on an Apple Silicon Mac against real apps; tasks work best with Claude.
3. **How it works.** The pipeline diagram and three sentences: the on-device grammar handles common commands, anything else goes to the model as a task, "stop" always halts it.
4. **Requirements.** As today.
5. **Install and first run.** `scripts/bundle.sh && open build/NoHands.app`, the Microphone and Accessibility grants in three numbered steps, Screen Recording as optional, the one-line note that each ad-hoc rebuild needs new grants (the `CODESIGN_IDENTITY` fix is linked), and the menu-bar mode labels `CMD`, `DICT`, `ZZZ`.
6. **Try these.** About 12 phrases in a short list: `open safari`, `go to youtube.com`, `show numbers` then `click 12`, `scroll down 10`, `start dictating`, `stop dictating`, `new tab`, `play`, `volume 40`, `select the last sentence`, `go to sleep`, `wake up`, `stop`, and one natural-language request. A link to `docs/voice-commands.md` for the full list.
7. **Claude or a local model.** A few lines: with no setup the grammar works, and natural-language commands use the local model and show `local model not running: start Ollama` until it is set up (`LLM off` only for `intentBackend` `off`, or `claude` with no key). Set a Claude key from the menu (**Set Claude API key…**), or run `scripts/setup-local-model.sh` for Ollama. The **Model** menu item switches between them. Links to `docs/configuration.md`.
8. **Configuration.** Kept as a short `## Configuration` section so `AGENTS.md` and `THIRD_PARTY_LICENSES.md` still land: the file path `~/.config/nohands/config.json`, every key optional, restart to apply, how to set the API key (menu, file or `ANTHROPIC_API_KEY`), and a link to `docs/configuration.md`.
9. **Privacy.** Kept as a `## Privacy` section so `SECURITY.md` still lands: four lines (audio stays on the Mac, only unmatched commands go to the model as text, the local backend keeps everything on loopback, there is no wake word so say "go to sleep") and a link to `docs/privacy.md`.
10. **More docs.** One list linking the six pages, `nohands-cli` (`docs/cli.md`), and the design spec.
11. **Contributing.** `swift build`, `swift test`, the four source targets in one line each, PR rules in three lines (one ticket, one branch, one PR; conventional commits; a new voice phrase goes in `docs/voice-commands.md` in the same PR), and a link to `CONTRIBUTING.md`.
12. **License.** As today, including the model licences and the 3B Qwen note. Security and contributing links.

Plain sentences, no em dashes (`human-writing`).

### `CONTRIBUTING.md`

Keep its sections and refresh them:

- **Before you start.** Branch and PR rules: one issue, one branch (`feat/nh-N-short-title`), one PR, never from `main`, link the issue with `Closes #N`, fill in the PR template.
- **Build, test, run.** `swift build`, `swift test`, `scripts/bundle.sh && open build/NoHands.app`, the stable-signing tip so a contributor is not re-granting permissions on every build, and `log stream --predicate 'subsystem == "dev.nohands.app"'`.
- **Where code goes.** The table as today, plus the per-app pack rule (`Sources/NoHandsCore/AppPack.swift` and a row in the per-app table).
- **Commits.** As today.
- **Labels.** Area labels `core`, `mac`, `cli`, `docs`; type labels `type:feature`, `type:improvement`, `type:bug`.
- **Tests.** Kept as today (it already matches `AGENTS.md` § Testing in a contributor's words).
- **Checking behaviour by hand.** The intent fixtures as today, plus `nohands-cli parse` for grammar changes, `nohands-cli bench` for latency (with `scripts/make-bench-audio.sh` and `Tests/Fixtures/audio/README.md`), and `nohands-cli scenarios` for task changes (it takes over the screen, so run it on a spare desktop). Each in one or two lines, linking `docs/cli.md`.
- **Manual checks, Secrets and privacy, License.** As today. The voice-table line points to `docs/voice-commands.md`.

It stays a guide for a human contributor and does not copy the agent-team rules from `AGENTS.md`.

### How it is checked

A throwaway script in the scratchpad (not committed) runs before and after:

1. Word counts for `README.md` and `CONTRIBUTING.md`, written into the PR as a before and after table. README target: 1,500 words or fewer; it must be under 2,846 (half).
2. Every voice phrase in the two command tables, every CLI subcommand and every config key from the old README appears in the new README or `docs/*.md`, and every phrase row from the old tables is present word for word in `docs/voice-commands.md`.
3. Every backticked token in the old README appears somewhere in the new README or `docs/*.md`. Any that doesn't is listed and restored.
4. Every relative link in `README.md`, `CONTRIBUTING.md`, the new `docs/*.md` pages, `SECURITY.md` and `THIRD_PARTY_LICENSES.md` resolves to a file, and every `#anchor` resolves to a heading.
5. `git diff --stat origin/main` shows only `.md` files. No source file, `scripts/` file or `scripts/intent-eval*.json` changes.
6. `swift test` passes.

## Leaves out

- Editing `AGENTS.md`, `docs/agents/project.md` or `docs/superpowers/` beyond this spec (ticket's out of scope). See the first call below.
- `SECURITY.md`, `THIRD_PARTY_LICENSES.md` and `.github/`. Their README pointers still land because the README keeps `## Privacy` and `## Configuration`.
- Shortening the moved reference text itself.
- Changing any rule, behaviour, config default or source comment.

## Calls I made

- **The voice command table moves to `docs/voice-commands.md`, but `docs/agents/project.md` still names "the `README.md` voice command table"** in its Product rule and Docs check rows. The ticket puts `project.md` out of scope and that file is on the approval path, so I don't edit it. The README's Try these section names `docs/voice-commands.md` as the full voice command table, so the rule still has one table to point at. A follow-up ticket should repoint the Product rule, the Docs check extra checks and `AGENTS.md`'s "Key setup" line to the new pages. The alternative, keeping the 49-row table in the README, would leave the README at about 3,500 words and miss the ticket's target.
- **The README keeps short `## Configuration` and `## Privacy` sections** so the pointers in `AGENTS.md`, `SECURITY.md` and `THIRD_PARTY_LICENSES.md` still land without editing those files.
- **Six new pages, not one.** One reference page would be about 4,500 words. Split by what a reader is looking for: commands, CLI, config, using the app, tasks, privacy.
- **Moved text is moved, not rewritten.** Only headings, the opening line and relative links change. This keeps "do not lose a fact" checkable by diff.
- **The status line becomes "early software, run and measured on an Apple Silicon Mac against real apps; tasks work best with Claude."** The old line is contradicted by measured numbers in the repo. I don't claim more than the docs show.
- **Title is `# NoHands`,** per the brand rule, replacing `# nohands`.
- **Try these list** is my pick of about 12 phrases covering apps, web, targeting, dictation, media, editing, sleep and stop.
- **The Layout and Design sections fold into More docs and Contributing.**
- **No plan file.** The ticket changes only markdown, so the build goes from this spec (`kickoff-feature` step 6).
- **The check script stays out of the repo,** as in NH-99.
- **This spec's status** is Draft until approved, then Shipped at closeout.
