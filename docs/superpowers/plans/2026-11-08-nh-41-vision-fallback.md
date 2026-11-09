# NH-41 Vision Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On the Claude backend, with `visionFallback` on, send a picture of the focused window on the steps where the accessibility tree failed, and click what the model sees.

**Architecture:** Pure logic (triggers, coordinate mapping, request building, config) in `NoHandsCore` with table tests. A `ScreenshotProviding` seam in `NoHandsMac` with a ScreenCaptureKit implementation. `TaskRunner` decides when to capture, attaches the picture to the `StepRequest`, maps picture points to screen points and checks the window before acting.

**Tech Stack:** Swift 6 strict concurrency, ScreenCaptureKit (`SCScreenshotManager`), CoreGraphics, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-08-nh-41-vision-fallback-design.md`. Read it with this plan.

## Global Constraints

- No `@unchecked Sendable` and no `@preconcurrency` in product code (test fakes may follow the existing `@unchecked Sendable` pattern in `Tests/`).
- `NoHandsCore` imports no AppKit, ScreenCaptureKit or network code.
- `visionFallback` defaults to `false`; `visionEnabled = visionFallback && effectiveBackend == .claude`. With it off, the request body and schema are byte-identical to today.
- Image: JPEG quality 0.7, longest side at most 1200 px, never upscaled, in memory only, never logged.
- Capture deadline 2 s (constant). `cancel()` must end a task without waiting for a hung capture.
- Window tolerance 2 pt. Image block goes after the text blocks, media type `image/jpeg`.
- A point is valid only on a request that carried an image, must be the step's first action, and only one action per step may hold one.
- Failure strings: `point outside the screenshot`, `point must be the step's first action`, and `ActionExecutor.elementChanged` for a moved window. Row reasons: `screen recording not granted`, `screen capture failed`, `a menu or sheet is open`; the row for a picture step is `step n · looking at the screen`.
- Conventional commits, one commit per task. Test lines should not exceed feature lines.

## Review Focus

- A task with `visionFallback` on and a local backend: no capture, no picture, no `look` offered (Task 1, Task 3).
- `look` decoded on the Ollama/one-shot path: harmless no-op, never captures (Task 1).
- Point on a step with no picture is a screen point and untouched (Task 5).
- Capture throws or hangs after `cancel()`: task ends `.stopped` promptly (Task 5).
- Stuck on a request that carried an unavailable-picture line ends the task, no second call (Task 5).

---

### Task 1: `look`, config and trigger rule (Core)

**Files:**
- Modify: `Sources/NoHandsCore/Action.swift`, `Sources/NoHandsCore/IntentDecoder.swift`, `Sources/NoHandsCore/ActionSummary.swift`, `Sources/NoHandsCore/AppConfig.swift`, `Sources/NoHandsMac/ActionExecutor.swift` (and every other exhaustive `switch` on `Action` the compiler flags)
- Create: `Sources/NoHandsCore/VisionTrigger.swift`
- Test: `Tests/NoHandsCoreTests/VisionTests.swift` (new; later tasks append)

**Interfaces:**
- Produces: `Action.look`; `AppConfig.visionFallback: Bool` (key `visionFallback`, default false) and `AppConfig.visionEnabled: Bool`; `VisionTrigger.wantsPicture(lastFailure: String?, lastActions: [Action]) -> Bool`.

- [ ] **Step 1: Write failing tests** in `VisionTests.swift`, table-driven: `wantsPicture` is true for failure `"no element named 'x'"`, `ActionExecutor.elementChanged` text `"element changed, look again"`, and for `lastActions == [.look]` with nil failure; false for `"no label 3"`, `nil`/`[]`, and `"point off screen"`. Decoder: `{"actions":[{"kind":"look"}]}` decodes to `[.look]`. Config: default false; `{"visionFallback":true}` parses; `visionEnabled` is false when `intentBackend == .local` and true with a key and `.claude`.
- [ ] **Step 2: Run** `swift test --filter VisionTests`. Expected: compile failure / FAIL.
- [ ] **Step 3: Implement.** `.look` case; decoder `case "look": return .look`; `ActionSummary` kind `"look"`; executor runs `.look` as a successful no-op; config key in `CodingKeys` and `init(from:)`; `VisionTrigger` matches by `hasPrefix("no element")` and `hasPrefix("element changed")`. Do not add `look` to `IntentSchema.kinds` (Task 3 does the vision schema).
- [ ] **Step 4: Run** `swift test`. Expected: all pass, build clean under strict concurrency.
- [ ] **Step 5: Commit** `feat(core): look action, visionFallback config and picture trigger (NH-41)`.

### Task 2: Screenshot geometry (Core)

**Files:**
- Create: `Sources/NoHandsCore/ScreenshotGeometry.swift`
- Test: `Tests/NoHandsCoreTests/VisionTests.swift`

**Interfaces:**
- Produces:
  - `struct StepScreenshot: Sendable, Equatable { var jpeg: Data; var imageSize: CGSize; var windowFrame: CGRect; var app: String }`
  - `enum PointMapping: Equatable, Sendable { case mapped([Action]), refused(String) }`
  - `enum ScreenshotGeometry` with `static func imageSize(window: CGSize, backingScale: CGFloat, maxSide: CGFloat = 1200) -> CGSize`, `screenPoint(fromImage: CGPoint, shot: StepScreenshot) -> CGPoint`, `imagePoint(fromScreen: CGPoint, shot: StepScreenshot) -> CGPoint`, `mapPoints(_ actions: [Action], shot: StepScreenshot) -> PointMapping`.

- [ ] **Step 1: Write failing tests** (table-driven). `imageSize`: 1600×1000 window at scale 2 → longest side 1200, aspect kept; 400×300 at scale 1 stays 400×300 (never upscaled past real pixels); 400×300 at scale 2 stays 800×600 capped by 1200 not above. Mapping both ways for: Retina window at (100,50); window on a second screen at origin (−1440, 0); corners (0,0) and (imageSize). `mapPoints`: click, `moveCursor` and `drag(from:to:)` points rewritten; a point past the image edge → `.refused("point outside the screenshot")`; point in action 2 → `.refused("point must be the step's first action")`; two point actions → same refusal; `.click(.label(3), …)` and no points → `.mapped` unchanged.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** `screen = frame.origin + image × (frame.size / imageSize)`; `imageSize` = real pixels `window × backingScale` scaled down to `maxSide` if larger, whole pixels, each side ≥ 1. `mapPoints` inspects `.click(.point)`, `.moveCursor(.point)` and both ends of `.drag`; an out-of-bounds test uses `0...imageSize` inclusive.
- [ ] **Step 4: Run** `swift test --filter VisionTests`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(core): screenshot geometry and picture point mapping (NH-41)`.

### Task 3: Request building (Core + Claude resolver)

**Files:**
- Modify: `Sources/NoHandsCore/IntentStep.swift` (`StepRequest.vision`), `Sources/NoHandsCore/IntentSchema.swift`, `Sources/NoHandsCore/ClaudeRequestBuilder.swift`, `Sources/NoHandsMac/ClaudeIntentResolver.swift`
- Test: `Tests/NoHandsCoreTests/VisionTests.swift`, `Tests/NoHandsMacTests/ClaudeIntentResolverTests.swift` only if the resolver wiring needs a case

**Interfaces:**
- Consumes: `StepScreenshot` (Task 2).
- Produces: `enum VisionInput: Sendable { case image(StepScreenshot), unavailable(String) }`; `StepRequest.vision: VisionInput? = nil` (add as a defaulted stored property and init parameter); `IntentSchema.visionActionsJSONSchema: [String: Any]` (the full schema with `look` added to the `kind` enum); `IntentSchema.visionRules: String` (spec text verbatim); `ClaudeRequestBuilder.init(model:effort:vision: Bool = false)`.

- [ ] **Step 1: Write failing tests.** With `vision: false` and `request.vision == nil`, `body(request:)` equals the body from a builder built the old way (compare `Data`). With `vision: true` and `.image(shot)`: decoded JSON has `messages[0].content` ending in exactly one `{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":<base64 of shot.jpeg>}}`, a `Screenshot: attached below, WxH pixels` line in the text, the system text containing the `visionRules` marker, and the schema `kind` enum containing `look`. With `.unavailable("screen capture failed")`: no image block and the line `Screenshot: unavailable (screen capture failed).`. `vision: false` schema enum has no `look`.
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** Add the `Screenshot:` line just before `Request:` in `userBlocks`; the image block is appended in `body(request:)` after the text blocks. `systemText` and the schema depend only on the builder's `vision` flag so the cache prefix is stable. `ClaudeIntentResolver` passes `vision: config.visionEnabled`.
- [ ] **Step 4: Run** `swift test`. Expected: PASS, including existing intent fixtures tests.
- [ ] **Step 5: Commit** `feat(core): vision request building for Claude (NH-41)`.

### Task 4: Screenshot provider and permission (Mac)

**Files:**
- Create: `Sources/NoHandsMac/ScreenshotProvider.swift`
- Modify: `Sources/NoHandsMac/Permissions.swift`
- Test: none for the real provider (needs Screen Recording; listed as manual). The fake provider lands in Task 5.

**Interfaces:**
- Consumes: `StepScreenshot`, `ScreenshotGeometry.imageSize/imagePoint`, `OverlayMath.badgeOrigin`.
- Produces: `enum ScreenshotResult: Sendable { case image(StepScreenshot), notGranted, failed }`; `protocol ScreenshotProviding: Sendable { func capture(badges: [Int: UIElementInfo]) async -> ScreenshotResult }`; `struct WindowScreenshotter: ScreenshotProviding` (init takes `ax: any ElementProviding`); `Permissions.screenRecordingGranted() -> Bool`, `requestScreenRecording()`, `openScreenRecordingSettings()`.

- [ ] **Step 1: Implement `Permissions` additions** using `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess` and the `Privacy_ScreenCapture` settings URL.
- [ ] **Step 2: Implement `WindowScreenshotter.capture`** per spec § Capture: preflight → `.notGranted`; frontmost PID plus `ax.focusedWindowFrame()` matched to an `SCWindow` (layer 0, frame within 2 pt) via `SCShareableContent`; `.failed` on no match or any throw; `SCContentFilter(desktopIndependentWindow:)`, `SCStreamConfiguration` sized by `ScreenshotGeometry.imageSize`, `SCScreenshotManager.captureImage`; draw badges (elements whose frames fall inside the window, mapped with `imagePoint`); encode JPEG 0.7 with `CGImageDestination` into memory. Keep ScreenCaptureKit calls on one isolation domain so no unsafe annotations are needed.
- [ ] **Step 3: Run** `swift build`. Expected: clean under Swift 6 strict concurrency.
- [ ] **Step 4: Commit** `feat(mac): window screenshot provider and Screen Recording permission (NH-41)`.

### Task 5: Task loop integration (Mac)

**Files:**
- Modify: `Sources/NoHandsMac/TaskRunner.swift`, `Sources/NoHandsMac/VoicePipeline.swift`, `Sources/nohands-cli/main.swift`
- Test: `Tests/NoHandsMacTests/TaskRunnerTests.swift`, `Tests/NoHandsMacTests/Fakes.swift` (add `FakeScreenshots`)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces: `TaskRunner.init(..., screenshots: (any ScreenshotProviding)? = nil)`; `FakeScreenshots: ScreenshotProviding` that records capture calls and badge arguments, returns a scripted `ScreenshotResult`, and can be told to never return.

- [ ] **Step 1: Write failing tests** in the existing rig style (`FakeResolver` records `StepRequest.vision`):
  - A named click that fails with `no element named …` → exactly one capture, on the next step; a plain step → zero captures.
  - A `[look]` step → capture on the next step; badges already up reach `FakeScreenshots`; a `[look]`-only step does not hide badges, other acting steps still do.
  - `stuck` with no picture → one capture and a second resolve with the same step number that carries the image, and the retry does not increase `stepsRun`; `stuck` with a picture → task ends `.stuck`; capture `.failed`/`.notGranted` on the stuck path → ends at once, no second resolve, finish line names `screen recording not granted`.
  - `.notGranted` on a trigger → step resolves with `.unavailable("screen recording not granted")`, row text `step n · screen recording not granted`, task continues.
  - A step with a picture whose actions are `[click point]` → input saw the mapped screen point; out-of-bounds point → nothing clicked, history failure `point outside the screenshot`; point as second action → `point must be the step's first action`; window frame changed (set `ax.windowFrame`) → nothing clicked, history failure `ActionExecutor.elementChanged`.
  - No provider (nil) or `visionEnabled` false → behavior and requests identical to today (`vision == nil` on every request).
  - `observation.surface != nil` → no capture, `.unavailable("a menu or sheet is open")`.
  - `FakeScreenshots` set to hang, then `runner.cancel()` → `run` returns `.stopped` quickly.
  - The strings `VisionTrigger` matches equal what `ActionExecutor` produces (`ActionExecutor.elementChanged`; a real failed `.click(.element(named:))` on `FakeElements`).
- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement.** In `run`, after the settle and before `StepRequest` is built, compute `wantsPicture` from the previous step's failure and actions (track them locally); capture via a private `func captureCancellable(badges:) async -> ScreenshotResult` that races the provider against a 2 s `sleep` and `cancel()` using an unstructured task and a resume-once continuation (do not await the loser), checking `isCancelled` before and after. Attach `request.vision`. Stuck retry as spec. Before the guards: when the request carried an image and the actions hold a point, run `ScreenshotGeometry.mapPoints`, then the window check against `observer`/`ax` frontmost app and `focusedWindowFrame` (expose a small `ScreenObserver` accessor for the frame; tolerance 2 pt), recording the failure and skipping execution on refusal. Status row text per spec. In the badge-hide line, skip the hide when every action is `.look`. `VoicePipeline` and the CLI `task` command pass `WindowScreenshotter(ax: …)` only when `config.visionEnabled`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass; also run the intent fixtures per `docs/agents/project.md` to confirm no change: `.build/debug/nohands-cli eval scripts/intent-eval.json` (skip if it needs a model; note that in the PR).
- [ ] **Step 5: Commit** `feat(mac): vision fallback in the task loop (NH-41)`.

### Task 6: Menu item and docs

**Files:**
- Modify: `Sources/NoHands/AppDelegate.swift`, `README.md`
- Test: none (menu layout and copy are not tested).

**Interfaces:**
- Consumes: `Permissions.screenRecordingGranted/requestScreenRecording/openScreenRecordingSettings`, `AppConfig.visionEnabled`.

- [ ] **Step 1: Add "Grant Screen Recording…"** next to `accessibilityItem`: created, targeted, added to the menu, hidden unless `config.visionEnabled && !Permissions.screenRecordingGranted()` in `refresh()`; its action requests then opens the Settings pane.
- [ ] **Step 2: README.** `visionFallback` in the Configuration example and key notes; Screen Recording in the permissions list and the ad-hoc signature caveat (including that macOS may apply the grant only after a relaunch); a paragraph in the task section describing the three triggers, `look` and picture points; § Privacy states pixels leave the Mac only on those steps, only to Claude, never with the local model, focused window only, whatever it shows, never saved.
- [ ] **Step 3: Run** `swift build && swift test`. Expected: clean, all pass.
- [ ] **Step 4: Commit** `feat(mac): Grant Screen Recording menu item and docs for the vision fallback (NH-41)`.
