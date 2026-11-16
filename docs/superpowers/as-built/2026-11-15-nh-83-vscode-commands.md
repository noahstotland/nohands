# As-built: VS Code voice commands

**Shipped:** in PR #144
**Ticket:** NH-83
**Spec:** [2026-11-15-nh-83-vscode-commands-design.md](../specs/2026-11-15-nh-83-vscode-commands-design.md)

## Differs from the spec

- The spec lists bare-verb synonyms `format`, `rename`, `comment`, `uncomment`, `replace`, `debug`, `continue` and `breakpoint`. They are not shipped: a one-word phrase counts as a complete command, so it fires at once (and on the early pass) before the rest of a longer sentence arrives ("replace foo with bar" would press the replace chord instead of the NH-54 edit). Use `format document`, `rename symbol`, `toggle comment`, `comment line`, `find and replace` and `start debugging` / `continue debugging`.
