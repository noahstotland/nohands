# Contributing to NoHands

Thanks for helping. NoHands is a macOS menu-bar app that controls the Mac by voice. Read [README.md](README.md) first for how it works, what it needs and how it is configured.

## Build and test

```bash
swift build
swift test
```

`swift test` must pass on a Mac with no permissions granted and no Ollama running. A test that needs the microphone, Accessibility, a real app or a running model is not a unit test (see the manual checks below).

All targets build in Swift 6 language mode with strict concurrency. Do not weaken it: no `@unchecked Sendable`, no `@preconcurrency` imports. Fix the isolation instead.

## Where code goes

| Path | Holds |
|---|---|
| `Sources/NoHandsCore` | Pure logic with unit tests. No AppKit, CoreGraphics events or network |
| `Sources/NoHandsMac` | macOS integration: audio, speech, input events, accessibility |
| `Sources/NoHands` | The menu-bar app |
| `Sources/nohands-cli` | Dev tool to try each piece by hand |

## Commits and pull requests

- One change per pull request. Do not mix a fix with a refactor.
- Conventional commits: `feat:`, `fix:`, `docs:`, `infra:`, `chore:`. A scope in brackets names the target, for example `fix(mac):` or `feat(core):`.
- Open the PR from a branch, never from `main`. Link the issue it closes (`Closes #N`) and fill in the PR template.
- Add a line to the README voice command table in the same PR when you add a command phrase. Every listed phrase must keep working.

## Tests

Write tests for behavior that would hurt users if it broke without anyone noticing. Skip the rest.

Test:

- Everything in `NoHandsCore`: the command grammar, mode machine, intent decoding, dictation formatting, number words, label and grid mapping, task guards.
- Safety rules: "stop" is never merged, the shortcut guard, the Ollama loopback-only URL check, model output rejected by the schema.
- Config parsing and defaults, including invalid JSON and missing keys.
- Error paths that must not take down the pipeline or a task: model timeout, denied permission, stale job.

Do not test menu-bar or HUD layout and copy, constants and registries, framework behavior (AppKit, FluidAudio), or anything that needs a microphone, Accessibility, a real app or a running model.

Write one table-driven test per rule, not one per edge case. A test must be able to fail for a real bug. A review fix gets a new test only when it fixes a real bug. As a rough budget, test lines should not exceed the lines of feature code.

### Intent fixtures

`scripts/intent-eval.json` and `scripts/intent-eval-disfluent.json` hold phrases and the actions a model must return. They run against your configured backend (Claude spends API credit; a local Ollama model does not):

```bash
swift build
.build/debug/nohands-cli eval scripts/intent-eval.json
.build/debug/nohands-cli eval scripts/intent-eval-disfluent.json
```

Both must keep passing. Never edit a fixture's expectations to make them pass. Fix the prompt or the grammar instead.

## Manual checks

These cannot run in `swift test`. Run the ones your change touches, and say in the PR which you ran and which you did not.

- [ ] Microphone: the app hears you and does not start without permission.
- [ ] Accessibility: typing, clicking and reading UI elements work, and the menu shows the grant item when it is missing.
- [ ] A real app: the command or task works in the frontmost app (Safari, Finder or the app you changed it for).
- [ ] A running model: a natural-language command works with Claude or with Ollama, and "LLM off" still shows when neither is set up.
- [ ] "stop" halts a running task.

Build and run the app with `scripts/bundle.sh && open build/NoHands.app`.

## Secrets and privacy

- Never commit `.env`, API keys or tokens. The Anthropic key lives only in `~/.config/nohands/config.json` or the `ANTHROPIC_API_KEY` environment variable.
- Do not paste API keys or private transcripts into issues, pull requests or logs.
- Report security problems privately, see [SECURITY.md](SECURITY.md).

## License

NoHands is under the [Apache License 2.0](LICENSE). Under section 5 of that license, any contribution you submit is under the same license, with no extra terms. Third-party notices are in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
