# maestro learnings store

Durable cross-run learning for the maestro engineering loop. The `compound` skill
writes here: every blocking finding a cross-review loop catches is captured as an
entry under `<category>/<category>.md`, fed into future acceptance contracts,
promoted into gates when it recurs, and retired when it goes quiet.

This directory starts empty by design. Entries are written ONLY from real
cross-review findings, never seeded by hand: a store padded with guesses routes
noise into every future contract. See `maestro/skills/compound/SKILL.md` for the
entry schema and the capture / retrieve / promote / garbage-collect procedure.

## Entry format

Each entry in `<category>/<category>.md` follows this shape. This is the format
only, not a learning; do not commit it as an entry:

```
- category: <stable-slug>
  root_cause: <one line, the cause not the symptom>
  contract_gap: <which acceptance-contract field would have caught it>
  fix: <the concrete correction applied>
  do_not_apply_when: []
  count: 1
  last_seen: <PR ref, YYYY-MM-DD>
```
