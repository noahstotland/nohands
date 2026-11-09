# As-built: Shrink the Claude step schema

**Shipped:** in PR #108
**Ticket:** NH-104
**Spec:** [2026-11-09-nh-104-shrink-claude-step-schema-design.md](../specs/2026-11-09-nh-104-shrink-claude-step-schema-design.md)

## Differs from the spec

- The spec left schema key order alone. It shipped fixed: `ClaudeRequestBuilder` builds the whole request as `OrderedJSON`, so
  `intent`, `status`, `actions` and each branch's `kind` come out in declared order, and the request is byte-stable. The live eval
  showed order matters (Haiku 37% and 0% scrambled, 70% and 78% ordered).
