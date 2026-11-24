# NH-79 Mail voice commands: Plan

Spec: `docs/superpowers/specs/2026-11-15-nh-79-mail-commands-design.md` (approved). Test command: `swift test`; typecheck: `swift build`.

## Task 1: Mail pack
- Add `Sources/NoHandsCore/MailPack.swift` (`extension AppPack { static let mail }`, bundle ID `com.apple.mail`), modelled on `TerminalPack.swift`, with the phrase table from the spec. Use `.pressKey` chords from the spec; `sent` phrases are `.menuItem("Mailbox > Sent")` unless `MenuMatch` path syntax needs another form (check `MenuMatch.firstMatch`: a `>` path limits the search to that menu). Add any missing `Key` cases to `Keys.swift` only if needed (arrow keys, delete, digits, letters).
- Register: `AppPacks.all = [.terminal, .mail]` in `AppPack.swift` (one-line change; siblings add their own).

## Task 2: Test
- `Tests/NoHandsCoreTests/MailPackTests.swift`, table-driven like `TerminalPackTests.swift`: a sample per spec group with Mail in front (include "go to the inbox", "open a new message"); same phrases not resolving to the Mail action in Safari or no app; globals (`delete`, `up`, `down`, `undo`, `find`, `close window`, `stop`, `cancel`) unchanged in Mail; no Mail phrase is a stop phrase or contains "stop"; every phrase containing "send" has at least two words. Keep test lines below feature lines.

## Task 3: Docs
- Add Mail rows and the toggle/global notes to the Per-app commands table in `docs/voice-commands.md` (per spec "docs/voice-commands.md" section). Remove nothing.

## Done when
`swift build` clean and `swift test` green; commit `feat: Mail voice commands (NH-79)`; push only `feat/nh-79-mail-commands`.
