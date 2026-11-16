# As-built: Installable app packs

**Shipped:** in PR #142
**Ticket:** NH-80
**Spec:** [2026-11-15-nh-80-installable-packs-design.md](../specs/2026-11-15-nh-80-installable-packs-design.md)

## Differs from the spec

- The spec lists no `version` or `author` on built-in packs; `AppPack` now carries `id`, `version` and `author` (Terminal: `terminal`, author `NoHands`).
- The validator also rejects an empty `commands` list, a command with no phrases, control/format/bidi/line-separator characters in any string, and whitespace in URLs. A phrase is also checked against the reserved list with its "open" or "go to" lead stripped.
- `PackSummary` does not hold "replaces version X" or "shadowed by installed packs"; `nohands-cli pack add` derives those from the store and `PackSet.shadowed`.
- `PackFile.encode` skips a command holding an action the format cannot express (the built-ins have none).
- `nohands-cli parse` also loads installed packs, so authors can dry-run a phrase.
- The grammar is swapped on reload through `CommandGrammar.with(packs:)` and `ModeMachine.use(grammar:)`, with the merge window's copy behind a lock in `VoicePipeline`.
- After security review the validator also: allows at most 2 plain (no command/control/option) key presses per command, no Return/space after a `menu_item`, rejects Command-Space, Command-Tab, Command-Option-Escape and the Empty Trash chords (unless the phrase says "empty" and "trash"), requires `open_app`/`open_url` to be a command's last action, holds menu titles that are word subsets of a guarded verb ("Empty"), and rejects `open_url` hosts that are IP literals, `localhost`, `.local` or have no dot.
- `PackSummary` counts any phrase the grammar already parses (patterns included) as an override, also when only its lead-stripped form parses.
- Second review round: menu paths are judged by the part after the last `>` (`IrreversibleGuard.held` and `namesLoosely`); `namesLoosely` also holds name fragments ("Emp", "Plac") and "Check" ("check out" merged to "checkout"). The "empty" + "trash" exemption covers only the delete chords; command-option-delete is blocked like command-shift-delete; command plus space or tab is always rejected. A return-like press (return, space, control-m, control-j, control-return) is rejected after a `menu_item` or any command chord, and control-letter chords count toward the 2-plain-key limit. `open_url` hosts must be ASCII letters, digits, `.` and `-` (punycode form), with no `%`, empty label, trailing dot, or `.lan`, `.internal`, `.home.arpa` suffix; a public name can still resolve to a private address. The install summary lists every phrase with its actions (`PackSummary.commandLines`) and prints pack text through `PackSummary.printable`.
- At most 100 packs load or install; `pack.json` is read up to 64 KiB + 1 bytes; the app coalesces `com.nohands.packs-changed` to one reload per 500 ms.
