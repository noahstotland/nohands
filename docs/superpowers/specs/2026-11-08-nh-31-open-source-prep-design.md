# NH-31: Prepare the repo for open sourcing

**Date:** 2026-11-08
**Status:** Shipped
**Ticket:** [NH-31](https://github.com/noahstotland/nohands/issues/31)
**Shipped:** in PR #89, with differences: [as-built](../as-built/2026-11-08-nh-31-open-source-prep.md)

## Goal

Leave the repo ready to be made public under a proper licence, while it stays private. The owner reads one audit report, decides, and flips visibility by hand. No source behaviour changes.

## Findings (2026-11-08, `d525aab`)

- `.claude/`, `scripts/cos_*.py` and most of `docs/agents/` are untracked but still in history (65 paths), so going public exposes them unless the owner decides otherwise.
- NoHands uses only `VadManager`, `AsrManager` and `AsrModels` from FluidAudio, so the Sortformer model and its NVIDIA licence are never downloaded.
- The app statically links FluidAudio, so a handed-out `.app` owes the Apache-2.0 notices. `scripts/bundle.sh` copies no licence file.
- Private-data grep: one home path in the harness plan, one fake test key, no secret files ever.

- FluidAudio 0.18.2 (compiled in): Apache-2.0, no `NOTICE`, has `ThirdPartyLicenses/`.
- Silero VAD (downloaded): MIT; the upstream README badge wrongly says CC BY-NC.
- Parakeet TDT v2 (default) and v3 (downloaded): CC-BY-4.0, attribution needed. The v3 Core ML page body says Apache-2.0, a conflict.
- `qwen2.5:7b-instruct` (pulled via Ollama): Apache-2.0.
- `qwen2.5:3b-instruct` (pulled via Ollama): **Qwen Research License, research only; commercial use needs Alibaba Cloud.**

`AppConfig` defaults to the 3B model on Macs under 12 GB and `setup-local-model.sh` pulls it. NoHands does not ship it, but a commercial user there would be outside its terms unless told.

## Owner decisions

1. Licence: Apache-2.0 recommended (permissive, patent grant, matches FluidAudio).
2. Copyright: `Copyright 2026 Noah Stotland`; `LICENSE` only, no SPDX headers.
3. Code of Conduct contact: no default; that file waits.
4. Qwen 3B: keep as the low-memory default, flag it, file a follow-up. Changing it is a source change.

## Design

- `LICENSE`: the chosen licence verbatim.
- `THIRD_PARTY_LICENSES.md`: one entry per table row (licence, source, compatibility, attribution), stating models are downloaded not shipped. Adds FluidAudio's `LICENSE` and compiled-in `ThirdPartyLicenses/` entries, the Parakeet credit, flagged Qwen 3B and v3 conflicts, and a line that a built `.app` must carry both files.
- Scan: pinned, checksum-verified gitleaks in the scratchpad over the tree and a `git clone --mirror` (branches, tags, `refs/pull/*`), plus grep for keys, tokens, home paths, emails and private URLs, also over issue and PR text. History is reported, never rewritten.
- Audit report in the PR: tool, refs, findings by file, commit and rule. It never quotes a matched value, because the PR becomes public.
- Content review: a keep, scrub or move list for the owner. Only the harness-plan home path is fixed up front.
- Community files: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md` (private reporting; transcripts private, Ollama loopback-only), a README licence section, markdown `.github/` templates.
- Order: do everything not waiting on the owner, open the PR with the audit, stop with `BLOCKED:`, then apply answers and run closeout and both reviews.

## Non-goals

- Making the repo public, rewriting history, CLA, CI, release pipeline, bundling models, changing the Qwen default or any source.

## Acceptance

- `LICENSE` matches the owner's choice; the third-party file covers every component.
- No quoted secret in the audit and no unresolved key or personal path in the tree (the fake test key stays, named as fake).
- Build and tests pass, nothing under `Sources/` or `Tests/` changes, the repo is still private at Done.

## Calls I made

- Qwen 3B is flagged, default left alone (no source change here).
- The scan also covers `refs/pull/*` and issue and PR text, since all go public.
- The build stops once after opening the PR; owner decisions can't precede the audit.
- `bundle.sh` stays as is (no release pipeline); the notice file says built apps must carry them.
- Parakeet v3 is recorded as CC-BY-4.0, conflict noted.
- `THIRD_PARTY_LICENSES.md`, not `NOTICE`; docs-only, so no plan file.
- The owner decides this ticket's specs and PR, since `.github/` is on the hands path.
