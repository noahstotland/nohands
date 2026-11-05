# As-built: NH-13 echo cancellation

**Shipped:** in PR #24
**Ticket:** NH-13
**Spec:** [2026-11-05-nh-13-echo-cancellation-design.md](../specs/2026-11-05-nh-13-echo-cancellation-design.md)

## Differs from the spec

- The spec says the converter takes channel 0 of a multichannel voice-processing format. What shipped copies channel 0 only into a mono buffer in the tap itself, before conversion. This also applies with `echoCancellation` off. The old path handed every channel to `AVAudioConverter`, which may already have used channel 0 for a mono output, so the change may be invisible for a multichannel microphone; it was not measured.

- The spec says to add the key to existing `AppConfigTests` table rows. No existing row fit, so a new test, `echoCancellationDefaultsOnAndParses`, covers the default and `false`.

## Checks that didn't run

- All six manual checks in the spec (they need a microphone and speakers), plus whether channel 0 carries the processed voice on real hardware.
