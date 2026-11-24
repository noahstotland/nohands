# NH-92: Status bar in the bottom-right corner: Plan

Spec: [2026-11-15-nh-92-status-bar-corner-design.md](../specs/2026-11-15-nh-92-status-bar-corner-design.md)

## Task 1: Core (tests first)

- `Sources/NoHandsCore/StatusBar.swift`: `StatusBarPosition` is `off, corner`; `stored` returns `.off` only for `"off"`, else `.corner`. `StatusBarText.line` returns `StatusLine?`; `.listening` + `.command` with no row returns `nil`.
- `Tests/NoHandsCoreTests/StatusBarTests.swift`: idle command gives nil (use `StatusBarText.line(...)?.text`); other cases unchanged; stored table (`nil`, `""`, `"top"`, `"bottom"`, `"middle"`, `"corner"` -> `.corner`; `"off"` -> `.off`).
- Verify: `swift test`.

## Task 2: Mac and app

- `OverlayController`: default `statusBarPosition = .corner`; `renderStatusBar` places the bar at `maxX - taskPanelInset - width`, `maxY - taskPanelInset - height`; nil line fades the panel out and clears `shownStatus` and `shownStatusFrame`; `renderBoard` drops the top-bar offset.
- `AppDelegate`: submenu titles "Off" and "Bottom Right" (a title per case); saved value is the raw value.
- Verify: `swift build`, `swift test`.

## Task 3: Docs

- `README.md` Status bar paragraph and `docs/superpowers/specs/2026-11-04-nohands-design.md` menu line, as the spec's Docs section says.
