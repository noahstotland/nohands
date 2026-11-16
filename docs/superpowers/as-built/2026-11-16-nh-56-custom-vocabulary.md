# As-built: Custom vocabulary

**Shipped:** in PR #145
**Ticket:** NH-56
**Spec:** [2026-11-16-nh-56-custom-vocabulary-design.md](../specs/2026-11-16-nh-56-custom-vocabulary-design.md)

## Differs from the spec

- The spec passes only a stop through unchanged. Shipped: `Vocabulary.rewrite` also passes mode and release phrases ("wake up", "stop dictating", "command mode") as heard, and discards a rewrite that would turn the words into a stop (for example `nether` to `never` making "never mind"), so the list cannot take a voice-only user's way out of a mode.
- A `vocabulary` value that is not a list counts as one skipped entry, so the launch log line appears; the spec said it is ignored.
- `EndpointReplay` also applies the vocabulary, so `endpoint-test` replays match the live pipeline.
