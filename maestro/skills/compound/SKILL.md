---
name: compound
description: Turn each cross-review loop's recorded blocking findings into durable prevention. Capture every blocking finding into the learnings store, feed matching traps into the next contract, promote a pattern that recurs into the contract and gates, and retire stale rules. Load when a cross-review loop terminates, and when authoring a new acceptance contract.
---

# compound — learn from every loop

Every blocking finding the cross-review loop caught is evidence of a gap that
let bad work through. Compounding turns that evidence into prevention so the
same defect cannot pass twice. The iron rule of WHERE the learning goes:
learning enters the QUESTIONS (the acceptance contract, the deterministic gates,
the reviewer's standing checklist), never the ANSWERS (a reviewer's verdict, or
any memory carried into a review). A rule written into the contract is shared
input the implementer is judged against too, not a hidden thumb on the critic's
scale, so it sharpens the work without corrupting the independent check.

The store fills only from real findings. Never invent an entry, never seed a
pattern you have not actually seen block a real PR. An empty store is correct
until the first loop records something; a store padded with guesses is worse
than none, because it routes noise into every future contract.

## The learnings store

One committed directory, `maestro/solutions/<category>/<category>.md`, one file
per finding category, grep-retrieved by area and never read whole into context.
Each entry is a short record:

- `category`: a stable slug for the defect class (e.g. `test-tampering`,
  `unhandled-async-rejection`, `missing-input-validation`).
- `root_cause`: one line on why it happened, not the symptom.
- `contract_gap`: which acceptance-contract field would have caught it had it
  been filled (usually a missing `known_failure_patterns` trap or a too-loose
  `acceptance_check`).
- `fix`: the concrete correction the implementer applied.
- `do_not_apply_when`: a global condition under which this rule is noise; `[]`
  when none. This is the ONLY suppression mechanism.
- `count`: the number of distinct PRs this category has blocked.
- `last_seen`: the PR ref and date of the most recent hit.

## Capture (on loop termination)

When `cross-review` finishes a PR (step 6 ready, or step 7 escalated), read the
blocking findings it recorded in the registry for every round and write each to
the store before the loop is considered closed:

- new category: create the entry with `count: 1`.
- known category: increment `count`, refresh `last_seen`, and add detail only if
  the new occurrence teaches something the entry did not already hold.

Capture is the ONLY write to the store, and its input is the registry's real
recorded findings, never a finding you imagine could happen.

## Retrieve (at contract authoring)

Before dispatching an implement task (`fanout`'s contract step), grep the store
by the task's area, the surfaces it touches, and the frameworks or libraries in
play. Every matching entry's `fix` becomes a line in that contract's
`known_failure_patterns`, unless the entry's `do_not_apply_when` holds for this
task. This is how a lesson re-enters the loop: as a named trap the
implementer reads and the QA verifier and reviewer judge against, identical input
for all three.

## Promote (after a pattern recurs)

When an entry's `count` reaches 2 the pattern is no longer a one-off; move it
from per-task retrieval into the standing layer, matched to how it is caught:

- mechanically checkable (a deletable test, a forbidden token, a missing guard):
  add it as a deterministic gate in `cross-review` step 2, where it blocks with
  no LLM judgement.
- statically reviewable but semantic (a design smell, a quietly weakened
  assertion): add one line to the `review` skill's standing checklist.
- behavioural: harden the contract template so `acceptance_checks` always covers
  that surface.

Each promotion is a normal maestro change: a small PR editing the relevant skill,
cross-reviewed by a different vendor like anything else. Promotion never edits a
reviewer's verdict or hands it a private list.

## Suppress noise globally, never per diff

If a rule fires on cases it should not, add a `do_not_apply_when` condition to its
store entry so retrieval skips it under that condition for every task. Never tell
a reviewer "do not flag X on this diff": a per-diff suppression is a hidden thumb
on the independent check and reintroduces exactly the blind spot the cross-vendor
property exists to remove.

## Garbage-collect

At capture time, while you are already touching the store after a loop, also
retire any rule that has blocked nothing in 30 consecutive PRs: it was either
fixed at the source or was never general. Drop it from the contract template, the
checklist, or the gate it was promoted into, and mark the store entry archived
with its final `last_seen`. The store must stay small enough to grep and trust; a
corpus that only grows rots into noise.

## The reviewer stays amnesic

Never load the store, or any learnings file, into a QA verifier's or reviewer's
context. The cross-vendor guarantee rests on two independent critics NOT sharing
priors; feed them a shared corpus and they correlate, which is the failure the
whole design exists to prevent. Learning reaches them only through the contract,
the standing checklist, and the gates, all shared inputs the implementer is
measured against too. The questions get smarter; the answers stay independent.
