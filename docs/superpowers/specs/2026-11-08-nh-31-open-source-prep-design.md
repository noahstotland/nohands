# NH-31: Prepare the repo for open sourcing

**Date:** 2026-11-08
**Status:** Draft
**Ticket:** [NH-31](https://github.com/noahstotland/nohands/issues/31)

## Goal

Leave the repo ready to be made public under a proper licence, while it stays private. After this merges, the owner can read one audit report, decide, and flip visibility by hand. No source behaviour changes.

## Today

Checked 2026-11-08 on `origin/main` (`d525aab`).

**The ticket is out of date in three places.**

- `.claude/`, `scripts/cos_*.py` and all of `docs/agents/` except `project.md` are no longer tracked, since the move to the machine install. They are still in git history (65 distinct paths under those folders across all refs), so going public exposes them unless the owner decides otherwise.
- History has 662 commits, not 81, and two author emails: `noahstotland@gmail.com` (230 commits) and `t3code@users.noreply.github.com` (432).
- The FluidAudio question is now narrower: see the table below.

**What NoHands actually uses.** Only `VadManager` and `AsrManager` / `AsrModels.downloadAndLoad` from FluidAudio. No diarizer, no text-to-speech. So the Sortformer model and its NVIDIA licence are never downloaded.

| Component | How it reaches the user | Licence, from the upstream page | Note |
|---|---|---|---|
| FluidAudio 0.18.2 (`e396cf7`) | Compiled into the app | Apache-2.0 | No `NOTICE` file in its root. It has a `ThirdPartyLicenses/` folder, and its library target also links a prebuilt `NemoTextProcessing` binary and a `FastClusterWrapper` target |
| Silero VAD (`FluidInference/silero-vad-coreml`) | Downloaded at run time | MIT | Upstream `LICENSE` is MIT, Copyright Silero Team. Upstream README badge alt text wrongly says CC BY-NC; the `LICENSE` file governs |
| Parakeet TDT 0.6b v2 (`FluidInference/parakeet-tdt-0.6b-v2-coreml`), the default | Downloaded at run time | CC-BY-4.0 | Commercial use allowed, attribution needed |
| Parakeet TDT 0.6b v3 (`FluidInference/parakeet-tdt-0.6b-v3-coreml`), `asrModelVersion: "v3"` | Downloaded at run time | CC-BY-4.0 on the NVIDIA page and the Hugging Face tag | The Core ML page body says Apache 2.0, which conflicts with its own tag |
| `qwen2.5:7b-instruct` | User pulls it through Ollama | Apache-2.0 | |
| `qwen2.5:3b-instruct` | User pulls it through Ollama | **Qwen Research License** | **Research or evaluation only. Commercial use needs a licence from Alibaba Cloud** |

**The Qwen 3B finding matters.** `AppConfig` picks `qwen2.5:3b-instruct` by default on any Mac with under 12 GB of memory (`AppConfig.swift:176`), and `scripts/setup-local-model.sh` pulls it there. NoHands does not ship the model, so this does not conflict with the repo's licence. But a person using NoHands commercially on such a Mac would be outside the model's terms unless told.

**First private-data pass** (grep only, the full scan is part of the build).

- Working tree: one home path, at `docs/superpowers/plans/2026-11-04-agent-desktop-harness.md:683`, which the ticket already names. No email addresses.
- One key-shaped string in the tree, `sk-ant-SECRET-KEY-123` in `Tests/NoHandsMacTests/ClaudeIntentResolverTests.swift:7`. It is a fake test value. A history grep for that pattern has one hit, and no `ghp_` or `github_pat_` hits.
- No `.env`, `.pem` or `.p12` file was ever added.
- Intent fixtures hold no owner names.

**Other facts.** The app binary statically links FluidAudio, so anyone handing out a built `.app` owes the Apache-2.0 notices with it. `scripts/bundle.sh` does not copy any licence file today. The repo is private (confirmed through the API). First commit is 2026-11-04.

## Owner decisions

The ticket reserves these for the owner. None is guessed. Answers in the spec approval save a stop later.

1. **Licence.** Recommended: **Apache-2.0**. Permissive, explicit patent grant, matches FluidAudio. The alternatives are laid out in § Approaches.
2. **Copyright line.** Recommended: `Copyright 2026 Noah Stotland`.
3. **SPDX headers.** Recommended: `LICENSE` only, no per-file headers.
4. **Code of Conduct contact address.** No recommendation on the address itself. A dedicated alias keeps a personal address out of the file. There is no default: without an answer this one file waits.
5. **Qwen 3B.** Recommended: keep it as the low-memory default, flag it in the third-party file and the README, and file a follow-up ticket to decide on a different default or a warning in the setup script. Changing the default is a source behaviour change and is out of this ticket.

## Design

Files are added in the repo root unless noted.

**`LICENSE`.** The owner's chosen licence, verbatim from the upstream source, with the agreed copyright line.

**`THIRD_PARTY_LICENSES.md`.** One entry per row in the table above: licence, source URL, whether it is compatible with the chosen licence, and the attribution it needs, with an opening statement that the models are downloaded at run time and not shipped in the repo or the app. Also:

- A verbatim copy of FluidAudio's `LICENSE` from the pinned commit.
- FluidAudio's `ThirdPartyLicenses/` entries that cover code compiled into the app (at least `fastcluster`, `NemoTextProcessing`, and anything the library target links). Entries for features NoHands never loads, such as the text-to-speech lexicons, are listed by name as not applying. The builder reads each one to confirm which side it falls on.
- CC-BY-4.0 credit for Parakeet: NVIDIA, the model name, the licence link, and a note that the Core ML conversion is by FluidInference.
- A flagged section for Qwen 3B quoting its limit and its required attribution text, and for the Parakeet v3 page conflict.
- A line saying a built `.app` handed to someone must carry `LICENSE` and this file.

**Secret and private-data scan.** gitleaks, a pinned release binary with its checksum verified, placed in the scratchpad and not installed on the machine. It runs on the working tree and on a `git clone --mirror` of the repo in the scratchpad, so every remote branch, `release-notes`, tags and `refs/pull/*` are covered. Then grep the same mirror for `sk-ant`, tokens, `.env` files, `/Users/noahstotland`, email addresses and private URLs.

Issue and PR text goes public with the repo too, so the same grep runs over issue bodies, PR bodies and comments, read through `gh.sh`. Anything found in history is reported, never rewritten.

**Audit report in the PR.** Tool and version, paths and refs scanned, findings. **The report names the file, commit and rule, and never quotes a matched value,** because the PR itself becomes public later.

**Content review.** Read `docs/superpowers/`, `docs/agents/project.md`, `README.md`, the intent fixtures, and the history-only tooling paths. Each item not meant for the public goes on a list with keep, scrub or move, for the owner. Replace the absolute path in the harness plan with a path that names no home directory. Nothing else is deleted or scrubbed before the owner decides.

**Community files.**

- `CONTRIBUTING.md`: `swift build`, `swift test`, conventional commits, the testing rules from `AGENTS.md`, and what needs manual checks because it needs the microphone or Accessibility.
- `CODE_OF_CONDUCT.md`: Contributor Covenant 2.1 verbatim from upstream, with the owner's contact address.
- `SECURITY.md`: how to report privately, and the guarantees: transcripts stay private, the Ollama URL is loopback-only, model output is untrusted.

**`README.md`.** A licence section naming the licence, linking `LICENSE` and `THIRD_PARTY_LICENSES.md`, and saying speech and local models have their own licences, naming Qwen 3B's limit.

**`.github/`.** `ISSUE_TEMPLATE/bug_report.md`, `ISSUE_TEMPLATE/feature_request.md`, `PULL_REQUEST_TEMPLATE.md` with the manual-check list, `Closes #N` and `## Release note`.

**Order of work.** The owner's content decisions can only follow the audit, so the build has one planned stop:

1. Do the scan, the third-party review, the path fix and every file that doesn't wait on the owner.
2. Open the PR with the audit report, the flagged list and the licence options. Stop with `BLOCKED:` listing every open owner decision.
3. Apply the answers, add `LICENSE` and finish the contact address, then run closeout and both reviews on the final head.

## Non-goals

- Making the repo public, or changing any visibility setting.
- Rewriting history or force-pushing.
- A CLA, a DCO check, CI, a release pipeline, signing or notarisation.
- Bundling any model or binary.
- Removing the agent-team tooling.
- Changing the low-memory model default, `scripts/bundle.sh`, or any source file.

Anti-goal: a report that leaks what it found. A public PR that quotes a real token or personal detail would be worse than no audit.

## Approaches

**Licence** (the owner picks).

- **Apache-2.0 (recommended).** Permissive, explicit patent grant, matches FluidAudio.
- **MIT.** Shortest and most permissive, no patent grant. Compatible with everything here.
- **GPL-3.0 or AGPL-3.0.** Keeps derivatives open, limits reuse, and sits awkwardly with a Mac app.
- **Source-available (BUSL or non-commercial).** Not OSI open source, listed so it can be ruled out.

**Where the third-party notices live.**

- **`THIRD_PARTY_LICENSES.md` (chosen).** A readable table plus the copied notices. A reader can see the Qwen 3B limit.
- **`NOTICE` alone.** Apache's usual place, but poorly suited to model terms and flags. NoHands has no notices of its own that need a `NOTICE` file.

**Scan tool.**

- **gitleaks (chosen).** Single binary, scans a git mirror directly.
- **trufflehog.** Also fine. Its verification mode calls live services with whatever it finds, which we don't want for a repo-only audit.

## Acceptance

- `LICENSE` matches the owner's choice, and the PR description records the options and the decision.
- `THIRD_PARTY_LICENSES.md` lists FluidAudio and every model above, each with licence, source URL and attribution, and any conflict is listed for the owner.
- The PR holds the audit report as described, with no matched secret value quoted. No unresolved secret, key or personal path remains in the tree. The `sk-ant-SECRET-KEY-123` test value stays and is named in the report as a fake.
- The flagged list is in the PR with the owner's decisions applied.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, the README section and the `.github/` templates exist, and their commands and paths are correct.
- `swift build` and `swift test` pass, and the diff touches no file under `Sources/` or `Tests/`.
- The repo is still private when the ticket is Done, confirmed through the API.

## Calls I made

- **`qwen2.5:3b-instruct` is flagged, and its default is left alone.** The ticket says no source behaviour changes, so a different default needs its own ticket.
- **The scan also covers `refs/pull/*` and the text of issues, PRs and comments.** The ticket asks for branches and tags, but all of these go public when the repo does.
- **The audit report never quotes a matched value,** because the PR becomes public too.
- **The build stops once, on purpose, after opening the PR.** The owner's decisions on flagged content can't exist before the audit. Reviews run after, on the final head.
- **Any built `.app` must carry the notices, and `scripts/bundle.sh` stays as it is.** The third-party file says so. Copying the files in the bundle script is a behaviour change, and there is no release pipeline yet.
- **The Parakeet v3 entry is recorded as CC-BY-4.0.** NVIDIA's page and the Hugging Face tag agree. The conflicting Core ML page body is noted beside it.
- **gitleaks runs from a pinned binary in the scratchpad,** so nothing is installed on the machine. No `.gitleaks.toml` is added to the repo.
- **The third-party file is `THIRD_PARTY_LICENSES.md`, not `NOTICE`.**
- **The `.github/` templates are plain markdown, not YAML issue forms.** Together with the rest of the diff, that makes this a docs-only ticket with no plan file.
- **This ticket's specs and PR are decided by the owner even in a No Hands run,** because the build adds files under `.github/`, which is on the hands path.
