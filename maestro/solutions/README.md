# maestro learnings store

Durable cross-run learning for the maestro engineering loop. The `compound` skill
writes here: every blocking finding a cross-review loop catches is captured as an
entry under `<category>/<category>.md`, fed into future acceptance contracts,
promoted into gates when it recurs, and retired when it goes quiet.

This directory starts empty by design. Entries are written ONLY from real
cross-review findings, never seeded by hand: a store padded with guesses routes
noise into every future contract. See `maestro/skills/compound/SKILL.md` for the
entry schema and the capture / retrieve / promote / garbage-collect procedure.
