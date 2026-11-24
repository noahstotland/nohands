# As-built: Slack voice commands

**Shipped:** in PR #141
**Ticket:** NH-81
**Spec:** [2026-11-15-nh-81-slack-commands-design.md](../specs/2026-11-15-nh-81-slack-commands-design.md)

## Differs from the spec

- The spec has `mute huddle`, `unmute huddle`, `mute myself` and `unmute myself` (⇧⌘Space). They are not in the pack: the pack validator that landed with NH-80 blocks any command-Space chord (launcher), and the user chose to drop the four phrases rather than loosen that guard. Slack's one huddle toggle (`huddle`, `leave huddle`, ...) stays.
- The spec makes `send`, `send message` and `send it` a plain Return. They now ask for a spoken yes first (the pack's `confirms`), because main's rule for built-in packs requires every phrase that names a guarded verb to ask (`builtInPhrasesThatNameAGuardedVerbAskFirst`, NH-149).
- Typing leads are merged per app in `PackSet` (`typingLeads(for:)`), like phrases and `confirms`, since NH-80 moved pack lookup there. The lead lives on `AppPack` and only built-in packs can have one: the pack-file format has no field for it.
