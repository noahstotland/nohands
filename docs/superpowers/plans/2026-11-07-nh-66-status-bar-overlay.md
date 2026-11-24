# NH-66 Status bar overlay: plan

Spec: [2026-11-07-nh-66-status-bar-overlay-design.md](../specs/2026-11-07-nh-66-status-bar-overlay-design.md)

1. Core: `StatusBar.swift` (`StatusBarPosition`, `StatusLine`, `StatusBarText.line`) and `StatusBarTests`.
2. Mac: `OverlayController` gets a status panel, `StatusBarView`, `setAppState`, `statusBarPosition`; the board moves below the bar when the bar is at the top; the bar hides while the grid or badges show.
3. App: `AppDelegate` reads and writes the `statusBarPosition` default, adds the Status Bar submenu, calls `overlay.setAppState` from `refresh()`.
4. Docs: README paragraph, architecture spec lines.
5. Verify: `swift build`, `swift test`.
