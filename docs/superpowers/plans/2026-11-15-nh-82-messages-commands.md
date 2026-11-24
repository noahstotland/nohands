# NH-82 Messages voice commands Implementation Plan

> Spec: `docs/superpowers/specs/2026-11-15-nh-82-messages-commands-design.md` (approved). One task.

**Files:** create `Sources/NoHandsCore/MessagesPack.swift`, `Tests/NoHandsCoreTests/MessagesPackTests.swift`; edit `Sources/NoHandsCore/AppPack.swift` (`AppPacks.all`), `docs/voice-commands.md`.

- [ ] Model `MessagesPack.swift` on `TerminalPack.swift`: `AppPack.messages`, name "Messages", bundle `com.apple.MobileSMS`, phrase groups exactly as the spec's table (chords: ⌘N, ⌃Tab, ⌃⇧Tab, ⌘F, ⌘I, ⌃⌘Space, ⌘T, ⌘W; `.menuItem("Mark as Unread")`, `.menuItem("Mark as Read")`, `.menuItem("Delete Conversation…")`).
- [ ] Register: `AppPacks.all = [.terminal, .messages]` (touch only that line).
- [ ] `MessagesPackTests.swift` like `TerminalPackTests`: Messages in front resolves samples from each group plus globals (`find`, `next tab`, `previous tab`, `search for mom` -> `.search("mom")`); Safari/nil do not resolve pack-only samples to the Messages action, and `close window` with Safari is still ⇧⌘W; no phrase is a stop phrase or has "stop" or "send" as a word; stop/cancel/cancel that unchanged with Messages in front.
- [ ] `docs/voice-commands.md`: Messages rows under Per-app commands plus the note from the spec § Docs. Remove no existing row.
- [ ] Verify: `swift build` and `swift test` green. Commit `feat: Messages voice commands (NH-82)`, push `feat/nh-82-messages-commands`.
