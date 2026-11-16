# NH-52: System controls by voice: Plan

Spec: `docs/superpowers/specs/2026-11-16-nh-52-system-controls-design.md` (approved; the user accepted the lock-screen
lockout risk and the Finder-only confirm for "empty trash").

Follow the `.media` / `.volume` / `parseTab` pattern already in the repo.

## Task 1: Core (`NoHandsCore`, no AppKit)

- `SystemCommand` enum (`lockScreen`, `screenshot(ScreenshotKind: screen|selection|window)`, `missionControl`,
  `showDesktop`, `space(Direction)` left/right only, `notificationCenter`, `openSettings(SettingsPane)`, `emptyTrash`),
  `Codable, Equatable, Sendable`; `Action.system(SystemCommand)`. Update every exhaustive `switch` over `Action`
  (summaries, plan/task guards, decoder: the model can't emit it).
- `SettingsPane` table: spoken names to macOS 14 pane ids (`x-apple.systempreferences:<id>`), per spec; `SettingsPane.parse(words)` nil for unknown.
- Grammar: fixed phrases in the exact table (lock, screenshot x3, mission control, show desktop, next/previous space,
  notification center, empty trash, with the extra forms in the spec); a `parseSettings` rule before `parsePattern` for
  `open settings for <pane>`, `open <pane> settings`, `<pane> settings`. `open <unknown> settings` keeps today's behaviour;
  `open settings for <unknown>` returns nil from `parse` and `rejection` gives `no settings pane called <x>: say open system settings`.
  Do not change `space`, `spotlight`, `open system settings`, VS Code `open settings`, `hide`, stop handling.
- Pure helper for the empty-trash decision from Finder's `WarnOnEmptyTrash` value (true/missing -> proceed, false -> refuse).
- Tests (one table each, small): grammar phrases + unchanged phrases + stop; pane names incl. unknown/empty; trash decision.

## Task 2: Executor (`NoHandsMac`)

`runSystem` in `ActionExecutor`, like `runMedia`:
- lock / screenshots: `input.press` chords (control-command-Q; command-shift-3; command-shift-4; window = command-shift-4 then space).
- Spaces: post control-left/right with fn + numeric-pad flags (extend the synthesizer with an opt-in parameter; ordinary `press` unchanged).
- Mission Control / Show Desktop: open `/System/Applications/Mission Control.app` (Show Desktop with argument `1`, via NSWorkspace configuration arguments).
- Notification Center: press the menu-bar clock (`com.apple.menuextra.clock`) through Accessibility; failure line if not found.
- Settings: `ax.open(url:appNamed:)` with the pane URL.
- Empty trash: read `WarnOnEmptyTrash` from `com.apple.finder`; refuse with the spec's line when explicitly false; activate Finder; press the `Empty Trash…` menu item (never option-held, never the chord); disabled -> `the Trash is already empty`.
- Pipeline: surface the pane rejection like the `spell` rejection.

## Task 3: Docs

Add the rows, pane list, empty-trash note and rebound-shortcut note to `docs/voice-commands.md`; no README table exists to edit.

## Verification

`swift build` clean (Swift 6 strict, no `@unchecked Sendable` / `@preconcurrency`), `swift test`, intent fixtures unchanged.
Manual macOS checks are listed in the PR, not run in tests.
