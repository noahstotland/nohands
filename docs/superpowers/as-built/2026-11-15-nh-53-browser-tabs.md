# As-built: NH-53 browser tabs by name and number

**Shipped:** in PR #133
**Ticket:** NH-53
**Spec:** [2026-11-15-nh-53-browser-tabs-design.md](../specs/2026-11-15-nh-53-browser-tabs-design.md)

## Differs from the spec

- The spec's prose says "go to the next tab" is control-tab; its must-not-change list says it stays as today. It ships as today: a reserved first word (`new`, `next`, `previous`, `first`, `last`, `other`) returns no tab command, so "go to the next tab" falls through to the `go` rule and types into the address bar. "open the new tab" still presses command-T.
- A name is also rejected (and falls through to today's behavior) when it has more than 8 words or has one of `then`, `open`, `go`, `switch`, `search`, `click`, `type`, `press` after its first word, so "open chrome and go to the youtube tab" stays with the model. A tab called "learn to go" cannot be named by voice.
- A named switch accepts "the", "a", "an" or no article.
- A number past the end of a read that was cut short says `can't read that far in <app>` instead of `only <k> tabs`.
