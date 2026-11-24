# As-built: NH-41 vision fallback for the task loop

**Shipped:** in PR #86
**Ticket:** NH-41
**Spec:** [2026-11-08-nh-41-vision-fallback-design.md](../specs/2026-11-08-nh-41-vision-fallback-design.md)

## Differs from the spec

- The first spec said a point action is mapped from picture pixels to screen points when the step has a picture, and left a point on a step with no picture as a screen point. Now, with `visionFallback` on, a point on a step with no picture is refused with `point needs a screenshot: say look first`, and the step runs nothing. A point repeated from history, or read as text from an earlier picture, would otherwise be clicked as a raw screen point and could land in another app. The refusal is also a picture trigger, so the next step gets a picture. With `visionFallback` off, points are screen points as before. The security review found this; the spec text was updated to match.
