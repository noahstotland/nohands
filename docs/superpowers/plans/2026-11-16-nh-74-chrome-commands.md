# NH-74: Chrome voice commands: Plan

Spec: `docs/superpowers/specs/2026-11-16-nh-74-chrome-commands-design.md` (approved). Build as the spec's phrase table
says. Chords and titles were checked against Chrome 157's live menu bar before this plan (System Events dump of
`AXMenuItemCmdChar` / `AXMenuItemCmdModifiers`): all match the table, with Downloads ⇧⌘J.

1. `Sources/NoHandsCore/ChromePack.swift`: `extension AppPack { static let chrome }` built like `VSCodePack.swift`
   (groups of phrases to actions), every phrase and action from the spec's table, bundle ID `com.google.Chrome`.
   Menu items use Chrome's exact titles: `Duplicate Tab`, `Pin Tab`, `Unpin Tab`, `Move Tab to New Window`,
   `Delete Browsing Data…`, `Extensions`. No phrase contains "stop".
2. `Sources/NoHandsCore/AppPack.swift`: append `.chrome` to `AppPacks.all` (one-line change, at the end).
3. `Tests/NoHandsCoreTests/ChromePackTests.swift`, table-driven, same shape as `VSCodePackTests.swift`:
   - every `AppPack.chrome` phrase, bare, with `open `, with `open a ` and `open the `, parses to its action with Chrome
     in front, and not to that action in Safari or with no app in front;
   - in Chrome, `open chrome` / `open safari` are `.openApp`, and `open file budget`, `open the downloads folder`,
     `open my last keynote`, `open system settings`, `close the other tabs`, `tab 3`, `stop`, `cancel` parse the same
     as with no app in front;
   - no Chrome phrase contains "stop".
   Keep test lines under the feature lines. The existing `builtInPacksRoundTripThroughTheFormat` and
   `shippedPacksAreWellFormed` cover the validator and normalization.
4. `docs/voice-commands.md` § Per-app commands: Chrome rows after the Messages rows, and one paragraph after the
   Messages paragraph (globals that also work in Chrome, `escape` stops a load, `open settings` means Chrome's settings
   there and `open system settings` still opens System Settings, `delete browsing data` only opens the dialog, no
   translate or reading mode phrase).
5. Verify: `swift build` and `swift test` clean; `.build/debug/nohands-cli parse` on a few phrases with Chrome as the
   app, if the CLI takes one.
