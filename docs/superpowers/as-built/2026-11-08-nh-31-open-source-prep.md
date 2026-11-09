# As-built: Prepare the repo for open sourcing

**Shipped:** in PR #89
**Ticket:** NH-31
**Spec:** [2026-11-08-nh-31-open-source-prep-design.md](../specs/2026-11-08-nh-31-open-source-prep-design.md)

## Differs from the spec

- The spec said history has 662 commits and two author emails. That count came from a local clone. The GitHub remote has 259 reachable commits (237 without merges), all by one email. The 432 commits by the `t3code` noreply address exist only locally and are not published.
- The spec said the agent-tooling paths in history are 65. On the remote it is 112 paths under `.claude`, `scripts` and `docs/agents`.
- The spec expected FluidAudio's Sortformer, TTS and G2P notices not to apply. The build found that Swift 6.0 compiles every FluidAudio target, and `scripts/bundle.sh` copies `FluidAudio_LuxTtsG2pResources.bundle` into the app. That data is derived from espeak-ng (GPL-3.0-or-later) and FrequencyWords (CC-BY-SA-4.0). It is recorded as an open item in `THIRD_PARTY_LICENSES.md` and the PR. A built app should not be handed out until a follow-up ticket stops the copy. `bundle.sh` is unchanged.
- `THIRD_PARTY_LICENSES.md` also reproduces the notices for the NemoTextProcessing, fastcluster, VBx and Japanese G2P code that is compiled in.
- A second open item was found: the Rust crates behind `rustfst` and `flate2` (`nom`, `miniz_oxide`, `bitflags`, `anyhow`, `lazy_static`) have no copyright line in FluidAudio's notice or upstream. `THIRD_PARTY_LICENSES.md` records it for the owner before any binary is handed out.
- `README.md` Layout lists the new root files and `.github`.
- `CODE_OF_CONDUCT.md` is not written. The owner has not given a contact address. Nothing links to it.
- The scan also covered issue and PR text. Issue #31 holds an absolute home path and the owner's email, listed in the PR for the owner.
- The PR holds a flagged list but no owner decisions on it yet, so none are applied.
- `SECURITY.md` says "no global input hooks" and adds the first-run speech model download as the one other network use. The stricter "acts only on the frontmost app" claim could not be verified in code, so it was dropped.
