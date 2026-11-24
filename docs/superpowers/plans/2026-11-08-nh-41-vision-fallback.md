# NH-41 Vision Fallback Implementation Plan

**Goal:** On the Claude backend, with `visionFallback` on, send a picture of the focused window on steps where the accessibility tree failed, and click what the model sees.

**Spec:** `docs/superpowers/specs/2026-11-08-nh-41-vision-fallback-design.md`. Read it with this plan.

## Architecture

Pure logic in `NoHandsCore`. A `ScreenshotProviding` seam in `NoHandsMac` over ScreenCaptureKit. `TaskRunner` decides when to capture, attaches the picture to the `StepRequest`, maps picture points to screen points, and checks the window before acting.

## Constraints

- `NoHandsCore` imports no AppKit, ScreenCaptureKit or network code.
- `visionFallback` defaults to false. `visionEnabled = visionFallback && effectiveBackend == .claude`. With it off, the request body and schema are byte-identical to before.
- Image: JPEG quality 0.7, longest side at most 1200 px, never upscaled, in memory only, never logged. It goes after the text blocks.
- Capture deadline 2 s, window tolerance 2 pt. `cancel()` must end a task without waiting for a hung capture.
- A point is valid only on a request that carried an image, only as the step's first action, and only one action per step may hold one.
- Failures: `point outside the screenshot`, `point must be the step's first action`, and `ActionExecutor.elementChanged` for a moved window.

## Review focus

- Local backend with `visionFallback` on: no capture, no picture.
- `look` on the Ollama or one-shot path never captures.
- A point on a step with no picture stays a screen point.
- Capture that throws or hangs after `cancel()`: task ends `.stopped` promptly.
- Stuck after an unavailable-picture request ends the task with no second call.

## Tasks

One commit per task.

1. **`look`, config, trigger (Core).** `Action.look` (decoder, summary, executor no-op), `AppConfig.visionFallback` and `visionEnabled`, `VisionTrigger.wantsPicture` matching failures that start with `no element` or `element changed`, or a last step of `[.look]`. `look` stays out of the base schema.
2. **Screenshot geometry (Core).** `ScreenshotGeometry` (image size capped at 1200, both-way point mapping, `mapPoints` over click, moveCursor and drag). Tests cover Retina, a second screen, and each refusal.
3. **Request building (Core + Claude resolver).** `VisionInput` (`image` or `unavailable`), `StepRequest.vision`, vision schema with `look`, `visionRules` text, `ClaudeRequestBuilder(vision:)`. System text and schema depend only on the builder flag, so the cache prefix is stable. A test checks vision off equals the old body.
4. **Screenshot provider and permission (Mac).** `ScreenshotProviding`, `WindowScreenshotter` (focused window, badges drawn, JPEG), Screen Recording permission helpers. Manual only.
5. **Task loop (Mac).** Capture on trigger via a cancellable race against the 2 s deadline; stuck retries once with a picture; point mapping and window check before acting; `FakeScreenshots`. Tests cover capture only on triggers, stuck paths, mapped and refused points, a moved window, an open menu or sheet, hang then cancel, and trigger strings matching what `ActionExecutor` produces.
6. **Menu item and docs.** "Grant Screen Recording..." shown only when `visionEnabled` and not granted; README covers the key, permission, triggers, and privacy (pixels leave the Mac only on those steps, only to Claude, focused window only, never saved).
