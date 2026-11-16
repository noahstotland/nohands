# As-built: NH-78 Finder voice commands

**Shipped:** in PR #169
**Ticket:** NH-78
**Spec:** [2026-11-16-nh-78-finder-commands-design.md](../specs/2026-11-16-nh-78-finder-commands-design.md)

## Differs from the spec

- The spec lists `trash file` and `delete file` as move-to-Trash phrases. They are not keys: the pack lookup also runs after a dropped `open` lead, so `open the trash file` (NH-58: a file called trash) would have trashed the selection in Finder. `trash this file`, `delete this file`, `move to trash` and the rest remain. The test checks that `open the trash file`, `open trash file` and `open delete file` do the same with Finder in front as without it.
- The spec says no NH-58 phrase changes in Finder. One does, on purpose: `open the new folder` (NH-58: a folder called "new") creates a new folder in Finder (⇧⌘N), because `new folder` is a key and `open a new folder` should work. That is harmless and `undo` removes the folder.
- The test covers every key in the pack, not one sample per group, and checks that with another app in front each key does what it does with no packs.
