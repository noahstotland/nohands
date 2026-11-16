# NH-78: Finder voice commands: Plan

**Spec:** [2026-11-16-nh-78-finder-commands-design.md](../specs/2026-11-16-nh-78-finder-commands-design.md)
**Ticket:** [NH-78](https://github.com/noahstotland/nohands/issues/78)

Goal: a built-in Finder pack (`com.apple.finder`), its table test and its rows in `docs/voice-commands.md`. Nothing
else in Core, Mac or the pipeline changes.

## Task 1: `Sources/NoHandsCore/FinderPack.swift`

- `extension AppPack { static let finder: AppPack }`, the shape of `MailPack.swift`: a `groups` list of
  `([String], [Action])` plus a loop that builds the `go to` keys for each place (`go to X`, `go to the X`,
  `go to my X`, `go to X folder`, `go to the X folder`, `go to my X folder`), with places and chords exactly as in the
  spec's table (`home` ⇧⌘H plus `go home`, `desktop` ⇧⌘D, `documents` ⇧⌘O, `downloads` ⌥⌘L, `applications` and `apps`
  ⇧⌘A, `icloud drive` and `icloud` ⇧⌘I).
- Every other group from the spec's phrase table, word for word. Menu items: `File > Close Window`,
  `File > Make Alias`, `File > Put Back`. ⇧⌘. is `KeyChord(.period, [.command, .shift])`.
- A doc comment saying: navigation keys are whole `go to` phrases so NH-58's `open …` phrases are untouched; no bare
  `delete`, `trash`, `home` or place name; `put back` is the menu item so it never trashes outside the Trash.
- Append `.finder` to `AppPacks.all` in `AppPack.swift`.

## Task 2: `Tests/NoHandsCoreTests/FinderPackTests.swift`

Two table tests, shaped like `MailPackTests.swift`, through `CommandGrammar()`:

1. `finderPhrasesRunOnlyInFinder`: one sample per group, including `go to the downloads folder`, `go to my
   documents`, `go home`, `open a new folder`, `put it back`, `paste here as a move`, `show hidden files`; each gives
   its action with `com.apple.finder` in front, and not that action with `com.apple.Safari` or nil.
2. `finderKeepsOpenFilesGlobalsAndNeverTrashesOnOneWord`: with Finder in front these parse the same as with no app
   in front: `open the downloads folder`, `open my documents folder`, `open trash`, `open file budget`, `open the
   reports folder`, `open my last keynote`, `open downloads`, `open home`, `empty trash`, `show desktop`, `home`,
   `delete`, `up`, `copy`, `paste`, `select all`, `undo`, `find`, `go back`, `new tab`, `stop`, `cancel`. `trash` and
   `go to trash` never give ⌘⌫ in Finder. No Finder key is a stop phrase or has the word "stop".

The NH-80 round trip test (`builtInPacksRoundTripThroughTheFormat`) and `shippedPacksAreWellFormed` cover the pack
through `AppPacks.all`; run them.

## Task 3: `docs/voice-commands.md`

Finder rows in the Per-app commands table (after the Messages rows), one per group, and a Finder paragraph after the
Messages paragraph, with the content in the spec's `docs/voice-commands.md` section. Don't touch other apps' rows.

## Verification

`swift build` and `swift test` green. Dry run a few phrases with
`.build/debug/nohands-cli parse "<phrase>" --app com.apple.finder` if that flag exists.
