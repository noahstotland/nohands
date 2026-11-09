# NH-75: Status bar not showing — Plan

**Spec:** [2026-11-08-nh-75-status-bar-not-showing-design.md](../specs/2026-11-08-nh-75-status-bar-not-showing-design.md)
**Ticket:** [NH-75](https://github.com/noahstotland/nohands/issues/75)

Three small edits, one commit each. No new unit test (spec § Tests): the change is AppKit panel state and a shell
script. `swift build` and `swift test` stay green.

## Task 1: the bar hides only when something is drawn

`Sources/NoHandsMac/OverlayController.swift`: replace

```swift
private var statusBarShown: Bool { statusBarPosition != .off && state == .none }
```

with

```swift
/// True while the grid or at least one badge panel is on screen. `state` can be `.labels([:])` with nothing drawn.
private var overlayDrawn: Bool { gridPanel != nil || !labelsPanels.isEmpty }
private var statusBarShown: Bool { statusBarPosition != .off && !overlayDrawn }
```

Update the doc comment above it. Leave `renderTaskPanel` and `state` as they are.

Check: `swift build`; rerun the scratch harness (`showLabels([:])` keeps the bar, `showGrid` hides it, `hide()`
restores it).

Commit: `fix(mac): keep the status bar up when show numbers draws no badges (NH-75)`

## Task 2: `scripts/bundle.sh` warns about a stale checkout

After `cd`, before `swift build`, add a best-effort check that never stops the build (`set -e` is on, so every
command in it is guarded):

- Skip unless `git rev-parse --git-dir` succeeds.
- `git fetch --quiet origin main || true`.
- If `origin/main` exists and `git merge-base --is-ancestor origin/main HEAD` fails, print to stderr
  `warning: building <branch>, <N> commits behind origin/main. Features merged since then will be missing.`
  with `N` from `git rev-list --count HEAD..origin/main` and `<branch>` from `git rev-parse --abbrev-ref HEAD`.

Check: run it on this branch (up to date: silent), then on a throwaway worktree at `HEAD~3` of main (warns, still
builds up to the `swift build` step; stop after the warning with a scratch copy that exits early, do not run a
second release build).

Commit: `fix: warn in bundle.sh when the checkout is behind origin/main (NH-75)`

## Task 3: README

`README.md` line 43 area, after the build command: one sentence saying to build from an up-to-date `main`, and that
`scripts/bundle.sh` warns when the checkout is behind.

Commit: `docs: say bundle.sh warns when the checkout is behind main (NH-75)`

## Then

`swift build` and `swift test`; compaction pass (nothing to compact: no agent text changed); open the PR with the
manual check from the spec.
