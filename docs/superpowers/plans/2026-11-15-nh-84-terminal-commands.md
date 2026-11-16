# NH-84: Terminal voice commands: Plan

Spec: [2026-11-15-nh-84-terminal-commands-design.md](../specs/2026-11-15-nh-84-terminal-commands-design.md). Branch
`feat/nh-84-terminal-commands`. Verification: `swift build` clean and `swift test` green after each task.

## Task 1: the pack (NoHandsCore)

- `Sources/NoHandsCore/TerminalPack.swift`: `extension AppPack { static let terminal }` with the spec's phrase table
  (bundle ID `com.apple.Terminal`); `AppPacks.all = [.terminal]` in `AppPack.swift`. Keys already normalized.
- `Tests/NoHandsCoreTests/TerminalPackTests.swift`: one table-driven test per rule in the spec's Tests section
  (Terminal in front incl. the global phrases; other app or none; no stop word and stop phrases unchanged).

## Task 2: README

- Terminal rows in the Per-app commands table, plus the sentence the spec describes.
