# As-built: Shrink the Claude step schema

**Shipped:** in PR #108
**Ticket:** NH-104
**Spec:** [2026-11-09-nh-104-shrink-claude-step-schema-design.md](../specs/2026-11-09-nh-104-shrink-claude-step-schema-design.md)

## Differs from the spec

- The spec left schema key order alone. It shipped fixed: `ClaudeRequestBuilder` builds the whole request as `OrderedJSON`, so
  `intent`, `status`, `actions` and each branch's `kind` come out in declared order, and the request is byte-stable. The live eval
  showed order matters (Haiku 37% and 0% scrambled, 70% and 78% ordered).
- The spec said the decoder changes in one place (a `0,0` drag source is rejected). It changes in three: `optInt` also reads `0` as
  omitted (it used to clamp `0` up to the minimum, so `wait` 100 ms and `timeout_ms` 500 ms), and `set_value` and `clipboard_set`
  are dropped when `value` is blank but `text` or `option` is filled. Both came out of code review.
- `max_tokens` for real steps is 2048, not 1024, because each action now carries about a dozen fields. The connection check still asks for 1.
- The spec's call to leave the harness prompt's `app_name (optional)` for `wait` is unchanged: that text is shared with the Ollama prompt.
