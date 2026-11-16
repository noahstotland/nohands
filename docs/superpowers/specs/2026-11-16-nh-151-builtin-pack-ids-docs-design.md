# NH-151: List every built-in pack id in the pack and CLI docs: Design

**Date:** 2026-11-16  **Ticket:** [NH-151](https://github.com/noahstotland/nohands/issues/151)
**Status:** Shipped
**Shipped:** in PR #176, as specified

## Intent

The docs should name every built-in pack id, so a reader knows which ids `pack builtin` takes and which ids a pack or registry may not use.

## Today (main at 9f78aae)

The ticket's "Today" section is out of date. `AppPacks.all` (`Sources/NoHandsCore/AppPack.swift:34`) now holds seven packs, and `docs/app-packs.md` already names them all in two places:

- Line 5 names the shipped packs by app: Terminal, VS Code, Mail, Messages, Safari, Finder and Chrome.
- Line 127, the `id` row: "Not a built-in pack's id: `terminal`, `vs-code`, `mail`, `messages`, `safari`, `finder` or `chrome`".
- Line 220, the registry rules: "no built-in pack id (`terminal`, `vs-code`, `mail`, `messages`, `safari`, `finder`, `chrome`)".

Two places still list only some of them:

- `docs/cli.md` line 25: "Prints a built-in pack (`terminal`, `chrome`, ...; an unknown id lists them)".
- `docs/app-packs.md` line 99: "(any built-in id works, such as `chrome`)".

I checked `swift run nohands-cli pack builtin <id>` for each of the seven ids, and each one prints its pack. An unknown id prints `built-in: terminal, vs-code, mail, messages, safari, finder, chrome`.

## Scope

- `docs/cli.md` line 25: replace `terminal`, `chrome`, ... with all seven ids in `AppPacks.all` order: `terminal`, `vs-code`, `mail`, `messages`, `safari`, `finder`, `chrome`. Keep "an unknown id lists them".
- `docs/app-packs.md` line 99: replace "such as `chrome`" with a pointer to the full list in the `id` row of the field table below it ("any id in the `id` row below works").
- Leave lines 5, 127 and 220 as they are, since they already match the code.

Acceptance: every built-in id list in the docs equals `AppPacks.all.map(\.id)`. A reviewer runs `swift run nohands-cli pack builtin <id>` for each id.

## Non-goals

- A test that compares the docs to the code (out of scope per the ticket).
- Pulling the three full lists into one shared section. Each list sits where a reader needs it (the CLI table, the field table, the registry rules).
- Any change to code or to the CLI usage text.

## Calls I made (surprising first)

- The ticket's "Today" section is stale: most of the fix already shipped with the per-app pack PRs. This PR fixes only the two partial lists still left.
- I listed all seven ids in each place (the ticket allows either approach). One shared section linked from the others would mean more edits for a small gain.
- In `docs/app-packs.md` line 99, the sentence points to the `id` row instead of adding a fourth copy of the list.
- The ids go in `AppPacks.all` order, the same order the CLI prints.
- No plan: the ticket changes only markdown, so the build works from this spec.
