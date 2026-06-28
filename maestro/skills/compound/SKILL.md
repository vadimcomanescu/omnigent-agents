---
name: compound
description: Turn each cross-review loop's recorded blocking findings into durable prevention. Capture every blocking finding into the docs/solutions store, feed matching traps into the next contract, promote a pattern that recurs into the contract and gates, and retire stale rules. Load when a cross-review loop terminates, and when authoring a new acceptance contract.
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

The store is `docs/solutions/` at the repo root, byte-compatible with Compound
Engineering's format so the same files are readable by either toolchain. No new
standard and no index file: discovery is grep over frontmatter, and the
directory is created on demand (`mkdir -p docs/solutions/<category>/`) on the
first real write. One file per learning, never one file per category:

    docs/solutions/<category>/<problem-slug>.md

`<category>` is a kebab-case defect class (`test-tampering`,
`integration-issues`, `missing-validation`). `<problem-slug>` is a kebab-case
title with no date prefix; the `date:` field is the canonical creation date.

Each file is YAML frontmatter plus fixed body sections:

```markdown
---
title: "One-line defect title"
date: 2026-06-28
last_refreshed: 2026-06-28   # add only when the same defect recurs
category: <subdirectory name>
module: <area or component the defect lived in>
problem_type: <stable defect-class slug>
component: <free-form area; CE's component enum is Rails-specific, do not import it>
severity: critical|high|medium|low
tags: [kebab, keywords, for, grep]
---

# One-line defect title

## Problem
The defect, stated as its root cause not its symptom.

## Symptoms
How it showed up in the diff or at runtime.

## What Didn't Work
The implementer's failed attempt, when the route-back recorded one. Omit if none.

## Solution
The concrete correction the implementer applied.

## Why This Works
Why that fix addresses the root cause.

## Prevention
The reusable trap: the acceptance-contract field that would have caught this
(usually a `known_failure_patterns` line or a tightened `acceptance_check`), and
the gate or checklist line it should become if it recurs. The rest of the loop
consumes this section.

## Related Issues
Every PR ref this defect has blocked, one per line. Two or more here means it
has recurred and is ready to promote.
```

## Capture (on loop termination)

When `cross-review` finishes a PR (step 6 ready, or step 7 escalated), read the
blocking findings it recorded in the registry for every round, and for each:

- grep `docs/solutions/<category>/` for a file already covering this root cause.
- no match: `mkdir -p` the category dir and write a new file, `date` set, the PR
  ref the only line under `## Related Issues`, no `last_refreshed`.
- match: append the PR ref under `## Related Issues`, set `last_refreshed` to
  today, and add detail only if this occurrence teaches something new.

Capture is the ONLY write to the store, and its input is the registry's real
recorded findings, never a finding you imagine could happen.

## Retrieve (at contract authoring)

Before dispatching an implement task (`fanout`'s contract step), grep the store
frontmatter by the task's area, surfaces, and frameworks, on the `module`,
`component`, `tags`, and `title` fields (frontmatter is the index; there is no
database). Read the frontmatter of the hits, then the `## Prevention` section of
the strong matches. Each becomes a line in that contract's
`known_failure_patterns`. This is how a lesson re-enters the loop: as a named
trap the implementer reads and the QA verifier and reviewer judge against,
identical input for all three.

## Promote (after a defect recurs)

A file with two or more refs under `## Related Issues` (equivalently, one that
has been `last_refreshed`) is no longer a one-off; move its `## Prevention` from
per-task retrieval into the standing layer, matched to how it is caught:

- mechanically checkable (a deletable test, a forbidden token, a missing guard):
  add it as a deterministic gate in `cross-review` step 2, where it blocks with
  no LLM judgement.
- statically reviewable but semantic (a design smell, a quietly weakened
  assertion): add one line to the `review` skill's standing checklist.
- behavioural: harden the contract template so `acceptance_checks` always cover
  that surface.

Each promotion is a normal maestro change: a small PR editing the relevant skill,
cross-reviewed by a different vendor like anything else. Promotion never edits a
reviewer's verdict or hands it a private list.

## Suppress noise globally, never per diff

If a trap fires on cases it should not, narrow the scope stated in its
`## Prevention`, or archive the file if it is noise everywhere. Never tell a
reviewer "do not flag X on this diff": a per-diff suppression is a hidden thumb
on the independent check and reintroduces exactly the blind spot the cross-vendor
property exists to remove.

## Garbage-collect

At capture time, while you are already in the store after a loop, retire any
file that has blocked nothing in 30 consecutive PRs (judged by `last_refreshed`,
or `date` if never refreshed): it was fixed at the source or was never general.
Remove the trap from the contract template, checklist, or gate it was promoted
into, and move the file to `docs/solutions/archived/` with its final date. The
store must stay small enough to grep and trust; a corpus that only grows rots
into noise.

## The reviewer stays amnesic

Never load the store, or any learnings file, into a QA verifier's or reviewer's
context. The cross-vendor guarantee rests on two independent critics NOT sharing
priors; feed them a shared corpus and they correlate, which is the failure the
whole design exists to prevent. Learning reaches them only through the contract,
the standing checklist, and the gates, all shared inputs the implementer is
measured against too. The questions get smarter; the answers stay independent.
