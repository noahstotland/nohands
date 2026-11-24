# NH-80: Installable app packs: Plan

Spec: [design](../specs/2026-11-15-nh-80-installable-packs-design.md). Test command: `swift test`; typecheck: `swift build`.
Tests follow `AGENTS.md` § Testing: one table-driven test per rule; test lines must not exceed feature lines.

## Task 1: Core format, validator, PackSet (NoHandsCore)

- `AppPack` gains `id` (built-in: `terminal`). New `PackFile.swift`: `PackFile.parse(_ data: Data) throws(PackError) -> AppPack`, `PackFile.encode(_ pack: AppPack) -> Data`; limits and rejections exactly as the spec's Validator section (reserved phrases via `StopWords.isStop` and the global table's `.setMode/.releaseMouse/.hideOverlay` entries; `ShortcutGuard.blocked` and `IrreversibleGuard.held` per phrase). `PackError` carries a reason string with no file content.
- AppPack must keep `[String: [Action]]` phrases, so encode groups phrases with equal actions into commands.
- `PackSummary` (name, version, author, apps, phrase count, `open_url` hosts, `open_app` names, overridden global phrases).
- `PackSet`: ordered packs (built-ins first, then installed), merges per bundle ID, first claim wins, exposes `shadowed` (pack id, phrase, winner). `CommandGrammar.init(config:packs:)` takes a `PackSet` (default built-ins) and `parse` looks up through it; stop phrases never reach a pack.
- Tests (table-driven): validator accepts good, rejects each spec case; frontmost-only, stop never claimed, first wins and shadowed listed, built-in beats installed; guard-blocked chord stays rejected; built-ins round-trip through encode/parse.

Done when: `swift build` and `swift test` pass. Commit `feat(core): pack file format, validator and pack set (NH-80)`.

## Task 2: PackStore (NoHandsMac)

- `PackStore(root:)` using `ConfigFile`'s private-folder/file steps (symlinks refused, 700/600, temp file plus rename): `install(data)` (validate, write `packs/<id>/pack.json`; re-add replaces in place), `list()` (install order = folder creation time, ties by id; enabled flag from `disabled` marker; invalid packs listed with reason), `setEnabled`, `remove(id)` (id pattern check, refuse symlinked folder, deletes only that folder), `loadEnabled() -> [AppPack]`. Posts `com.nohands.packs-changed` distributed notification after a change.
- No network anywhere.
- Mac test with a temp directory: modes 700/600, symlinked folder and file refused, re-add keeps order, remove deletes only that folder.

Done when: `swift test` passes. Commit `feat(mac): pack store (NH-80)`.

## Task 3: CLI, menu bar, docs

- `nohands-cli pack add <file>` (summary, `Install? [y/N]` on stdin, no `--yes`), `pack list`, `pack remove <id>`, `pack builtin <id>`; usage text updated.
- Menu bar Packs submenu in `NoHands/AppDelegate.swift`: per pack On toggle, Remove (confirm alert), a status line; "No packs installed" when empty. Reload the grammar's `PackSet` on the notification and on menu open (swap on main actor).
- `docs/app-packs.md` (format, limits, how to write one, sample pack), links from `README.md`, `docs/cli.md` rows, one line in `docs/voice-commands.md`.

Done when: `swift build` and `swift test` pass; intent fixtures unaffected. Commit `feat: pack CLI, menu and docs (NH-80)`.
