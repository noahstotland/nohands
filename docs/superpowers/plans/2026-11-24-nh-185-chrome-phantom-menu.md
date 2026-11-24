# NH-185: Chrome phantom Apple menu: Plan

Spec: `docs/superpowers/specs/2026-11-24-nh-185-chrome-phantom-menu-design.md`

1. `DesktopSnapshot.isClosedSurface` in core, plus one table-driven test in `DesktopSnapshotTests`.
2. `ScreenObserver.observe`: when a reported surface's snapshot is closed, snapshot the window with no surface. Only the observer uses the reported surface; the other `surface:` arguments are model-chosen, so nothing else changes.
3. `swift build`, `swift test`, then a live Chrome rerun if possible.
