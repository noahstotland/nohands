# NH-83: VS Code voice commands: Plan

Spec: `docs/superpowers/specs/2026-11-15-nh-83-vscode-commands-design.md` (approved). Build as the spec's tables say.

1. `Sources/NoHandsCore/VSCodePack.swift`: `extension AppPack { static let vscode }` built like `TerminalPack.swift`
   (groups of phrases to actions), every phrase and chord from the spec's table. Step into is `.menuItem("Step Into")`;
   zen mode is two `.pressKey`s (⌘K, Z). No phrase contains "stop".
2. `AppPack.swift`: `AppPacks.all = [.terminal, .vscode]`.
3. `Tests/NoHandsCoreTests/VSCodePackTests.swift`, table-driven, same shape as `TerminalPackTests.swift`:
   VS Code in front (sample per row, lead forms, overrides, globals), other app / none, no stop, `replace x with y`
   with a focused field stays the NH-54 edit. Keep test lines under the feature lines.
4. `docs/voice-commands.md`: VS Code rows in the Per-app table plus the notes sentence from the spec.
5. Verify: `swift build` and `swift test` clean; `nohands-cli parse --app com.microsoft.VSCode` dry run on a few phrases.
