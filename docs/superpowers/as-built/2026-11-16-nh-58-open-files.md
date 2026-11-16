# As-built: Open files, folders and recent documents by voice

**Shipped:** in PR #165
**Ticket:** NH-58
**Spec:** [2026-11-16-nh-58-open-files-design.md](../specs/2026-11-16-nh-58-open-files-design.md)

## Differs from the spec

- The spec names the model's `open_file` fields `name`, `kind` and `folder`. They shipped as `text` (the words), `option` (the kind) and `value` (the folder key), because `kind` is the action discriminator and the Claude schema is at its size limit. The decoder ignores blank unused target fields, rejects a non-blank `url` and any `path`.
- A folder that matches several times says `say open the <name> folder`.
- A hit the guard refuses is dropped from the list; if every hit is refused, the first refusal shows. A file that is gone or unreadable (rule 5) says `can't read that file`.
- Several matches in a macro step say `several files match: say open file <words>`; in a model task, `several files match: ask the user to say open file <words>`. `<words>` is the spoken words.
- The pick closes on `stop()`, when a task starts, and on the next utterance that is not a number. Pause, sleep and a mode switch do not close it separately.
- There is no spoken "more" for lists over six; the hint says to say more words.
