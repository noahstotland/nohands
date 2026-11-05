# As-built: NH-13 echo cancellation

**Shipped:** in PR #24
**Ticket:** NH-13
**Spec:** [2026-11-05-nh-13-echo-cancellation-design.md](../specs/2026-11-05-nh-13-echo-cancellation-design.md)

## Differs from the spec

- The spec says the converter takes channel 0 of a multichannel voice-processing format. What shipped copies channel 0 only into a mono buffer in the tap itself, before conversion. This also applies with `echoCancellation` off: a multichannel microphone that used to be mixed down now uses channel 0.
- The spec's `reportedEcho` flag was not needed: `.echoCancellation(Bool)` is emitted from `start()`, which rebuilds never pass through.

## Checks that didn't run

- All six manual checks in the spec (they need a microphone and speakers), plus whether channel 0 carries the processed voice on real hardware.
