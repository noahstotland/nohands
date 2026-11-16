# As-built: Remember routes that worked

**Shipped:** in PR #PRNUM
**Ticket:** NH-46
**Spec:** [2026-11-16-nh-46-route-memory-design.md](../specs/2026-11-16-nh-46-route-memory-design.md)

## Differs from the spec

- The spec says "Lakers game on espn" gets the Raptors route as a hint. It scores 0.5 against "open the Raptors game on espn" (`open` is not filler), so it does not match. "open the Lakers game on espn" scores 0.75 and does.
- The site-name check in the host rule uses any host label before the top-level one that is at least 3 characters long (`espn` for `espn.com`, `wikipedia` for `en.wikipedia.org`), not only the first label. A route with no host is never dropped by the host rule.
- `close_tab`, `select_tab` and `close_window` are stored by kind only, not by tab title (the name map is label number to title, and a tab number would collide with a label number). `go_to_tab` keeps its title. `press_key`, `scroll`, `move_window`, `drag` and `wait_for` are stored by kind only.
- `routeMemory` set to something that is not a bool falls back to `true` (as the spec says), but the other bool keys in `AppConfig` still reject a wrong type.
- After a backend switch the pipeline builds a new runner, so "forget that route" for the task before the switch says `no route to forget`. "forget all routes" still works.
- With `routeMemory` off the store is still read at launch, so "forget all routes" still empties the file. Matching and saving are off.
- The two forget rows are set by the pipeline, and a macro step that says "forget all routes" does what the spoken phrase does.
