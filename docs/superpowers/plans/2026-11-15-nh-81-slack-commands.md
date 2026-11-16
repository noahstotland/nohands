# NH-81 Slack voice commands Implementation Plan

> Spec: `docs/superpowers/specs/2026-11-15-nh-81-slack-commands-design.md` (approved). Follow it for every phrase, chord and call.

**Files:** modify `Sources/NoHandsCore/AppPack.swift`, `Sources/NoHandsCore/CommandGrammar.swift`, `Tests/NoHandsCoreTests/AppPackTests.swift`, `docs/voice-commands.md`; create `Sources/NoHandsCore/SlackPack.swift`, `Tests/NoHandsCoreTests/SlackPackTests.swift`.

## Task 1: Typing leads in packs
- [ ] Add `typingLeads: [String: [Action]]` (default `[:]`) to `AppPack` and its init (defaulted parameter, so Terminal and tests compile unchanged).
- [ ] In `CommandGrammar.parse`, after both pack exact lookups and before `menu <words>`: if a pack is in front (never for a stop utterance) and the normalized tokens start with a lead's tokens, return the lead's actions plus `.typeText(rest)`; rest comes from `rawWords` (case kept), drops one leading the/a/an and one trailing "channel"; empty rest returns the lead actions only. Fall back to the lowercased tokens if `rawWords` is nil.
- [ ] Extend `shippedPacksAreWellFormed`: leads normalized, non-empty, no stop word, not an exact phrase key.
- [ ] Test (in SlackPackTests): lead table incl. "jump to general", "Jump to the Design Team channel" -> types "Design Team", "jump to" (no typeText), Safari/no app -> not ⌘K.

## Task 2: Slack pack
- [ ] `SlackPack.swift`: `AppPack.slack` with bundle ID `com.tinyspeck.slackmacgap`, the spec's table (every phrase), lead `jump to` -> `[⌘K, .wait(ms: 300)]`; `AppPacks.all = [.terminal, .slack]`. Key enum names: check `Keys.swift` (use existing keys; add none unless a key is missing, e.g. period, comma, digit 1, up/down arrows).
- [ ] `SlackPackTests.swift`, table-driven on `CommandGrammar()`: sample per row in Slack; other app / none does not give the Slack action, `close window` stays ⇧⌘W elsewhere and is ⌘W in Slack; globals `go back`, `find`, `escape`, `mute` unchanged in Slack; no Slack phrase is a stop phrase or contains "stop"; "stop", "cancel" with Slack = with no app. Keep tests shorter than the feature code.

## Task 3: Docs
- [ ] `docs/voice-commands.md` § Per-app commands: Slack rows per spec group, the globals/mute/jump-to sentence, and the NH-76 sentence addition about leads. Keep every existing row.

## Verify
`swift build` and `swift test` clean; run the intent fixtures per project.md if the build allows. Commit per task (`feat(core): ...`), push to `feat/nh-81-slack-commands` only.
