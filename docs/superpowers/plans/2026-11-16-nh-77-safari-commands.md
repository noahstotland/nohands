# NH-77: Safari voice commands: Plan

**Spec:** `docs/superpowers/specs/2026-11-16-nh-77-safari-commands-design.md`
**Branch:** `feat/nh-77-safari-commands`

Shape: the Mail pack (NH-79). One Core file, one registry line, one test file, doc rows.

## Task 0: verification commands

- `swift build` (Swift 6 strict concurrency, clean)
- `swift test` (all green, no permissions, no Ollama)
- `swift run nohands-cli parse "go to the address bar" --app com.apple.Safari` prints the ⌘L action (dry run)

## Task 1: `Sources/NoHandsCore/SafariPack.swift`

- `extension AppPack { static let safari: AppPack = { ... }() }` in the style of `MailPack.swift`: a local
  `chord(_:_:)` helper, a `groups` array of `([String], [Action])`, flattened into `phrases`.
- Groups and actions exactly as the spec's phrase table (21 groups). `AppPack(name: "Safari", bundleIDs:
  ["com.apple.Safari"], phrases: phrases)` (id `safari`).
- Doc comment: Safari 17.5 menu titles; globals not repeated; toggles; view source needs the developer setting; no
  "stop" phrase.
- `AppPack.swift`: `AppPacks.all = [.terminal, .vscode, .mail, .messages, .safari]`.

## Task 2: `Tests/NoHandsCoreTests/SafariPackTests.swift`

Two table-driven tests, as `MailPackTests.swift`:

1. `safariPhrasesRunOnlyInSafari`: one sample per group, including lead forms (`go to the address bar`, `open a new
   private window`, `open downloads`, `go to history`), resolves to its action with `com.apple.Safari` in front, and
   not to it with `com.apple.mail` or `nil`.
2. `safariKeepsGlobalsAndNeverStops`: `new tab`, `close tab`, `close window`, `next tab`, `previous tab`, `reload`,
   `go back`, `go forward`, `find`, `zoom in`, `zoom out`, `actual size`, `home`, `tab 3`, `last tab`,
   `close other tabs`, `go to youtube`, `stop`, `cancel` parse the same with Safari as with no app. No Safari phrase
   is a stop phrase or contains the word "stop".

Round trip and well-formedness are covered by the existing tests once `.safari` is registered.

## Task 3: docs

- `docs/voice-commands.md` Per-app table: `Safari` rows after Messages, one per spec group (short phrases, what it
  does). Add the Safari sentence after the Mail sentence (globals work; toggles; view source setting; reopen closed tab
  reopens whatever closed last; tab by number is the global `tab 3`).
- `docs/app-packs.md`: the opening line names the shipped packs only as Terminal; leave it unless it lists all
  built-ins (it doesn't), and update the `Not terminal (a built-in pack)` id rule only if it lists every built-in.

## Done when

Task 0 commands pass; commit `feat: Safari voice commands (NH-77)`; push.
