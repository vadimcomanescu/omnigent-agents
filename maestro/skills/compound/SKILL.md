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

The store is `docs/solutions/` at the repo root, compatible with Compound
Engineering's format so the same files are readable by either toolchain.
"Compatible" means a file maestro writes is a CE solution file its tooling reads
and a CE solution file is one maestro can read; it does not mean CE follows its own
declared schema perfectly (CE declares a `component` enum it does not enforce,
and its real store uses far fewer category dirs than its declared map). No new
standard and no index file: discovery is grep over frontmatter, and the
directory is created on demand (`mkdir -p docs/solutions/<category>/`) on the
first real write. One file per learning, never one file per category:

maestro writes only CE's **Bug track** (`problem_type: bug`): every entry comes
from a cross-review or QA blocking finding, and those are defects. CE also
defines a Knowledge track for non-defect lessons; maestro does not write it,
because maestro's only learning source is caught defects, not general knowledge.

    docs/solutions/<category>/<problem-slug>.md

`<category>` is a kebab-case defect class (`test-tampering`,
`integration-issues`, `missing-validation`). `<problem-slug>` is a kebab-case
title with no date prefix; the `date:` field is the canonical creation date.

Each file is YAML frontmatter plus fixed body sections:

```markdown
---
title: "One-line defect title"
date: 2026-06-28
category: <subdirectory name>
module: <area the defect lived in>
problem_type: bug            # maestro writes only CE's Bug track
component: <free-form area, e.g. parser, auth-middleware; CE declares a component
            enum but does not enforce it, and its own files use free-form values>
symptoms: <one line: how it manifested in the diff or at runtime>
root_cause: <one line: the underlying cause, not the symptom>
resolution_type: <free-form CE class, e.g. code_fix, test_fix, config_change>
severity: critical|high|medium|low
tags: [kebab, keywords, for, grep]
# maintenance fields: last_refreshed is recurrence-only; related_pr mirrors
# ## Related Issues from first capture on; related holds solution cross-links:
last_refreshed: 2026-06-28   # set only on recurrence
related: [other-solution-slugs]   # cross-links to related learnings, not PRs
related_pr: [pr-refs]        # mirror of ## Related Issues, from first capture
---

# One-line defect title

## Problem
The defect in prose, stated as its root cause not its symptom; the `root_cause`
frontmatter field is the one-line grep version of this.

## Symptoms
How it showed up in the diff or at runtime, in prose; the `symptoms` frontmatter
field is the one-line grep version.

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
The DISTINCT PR refs this defect has blocked, one per line, each ref listed at
most once. This list is the count: its length is the number of distinct PRs that
exhibited the category. Two or more lines means the defect recurred across
separate PRs and is ready to promote; many findings of this category inside a
single PR are still one line, so one PR can never reach the threshold alone.
```

## Capture (on loop termination)

When `cross-review` finishes a PR (step 6 ready, or step 7 escalated), read the
blocking findings it recorded in the registry across every round, then collapse
them to the set of DISTINCT categories that fired in this one PR. Multiple
findings of the same category, whether in one round or repeated across rounds,
count as a single occurrence for this PR. For each distinct category:

- grep `docs/solutions/<category>/` for a file already covering this root cause.
- no match: `mkdir -p` the category dir and write a new file with `date` set, the
  PR ref as the only entry under `## Related Issues` and in `related_pr`, and no
  `last_refreshed`.
- match: if this PR ref is already listed under `## Related Issues`, the category
  was already recorded for this PR, so add nothing to the count; otherwise append
  the PR ref once under `## Related Issues` and to `related_pr`, set
  `last_refreshed` to today, and add detail only if this occurrence teaches
  something new. The ref appears at most once per file, so a single PR never
  pushes the count past one on its own.

Capture is the only path by which a new learning ENTERS the store, and its input
is the registry's real recorded findings, never one you imagine could happen. The
sole other writes are maintenance, the suppression edits and garbage-collect
archival below; no path seeds an invented entry.

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

A file with two or more DISTINCT PR refs under `## Related Issues` (equivalently,
one that has been `last_refreshed` by a later PR) is no longer a one-off; move its
`## Prevention` from
per-task retrieval into the standing layer, matched to how it is caught:

- mechanically checkable (a deletable test, a forbidden token, a missing guard):
  add it as a deterministic gate in `cross-review` step 2, where it blocks with
  no LLM judgement.
- statically reviewable but semantic (a design smell, a quietly weakened
  assertion): add one line to the reviewer's standing checklist in the
  `cross-review` skill, the doctrine the cross-vendor reviewer reads.
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
file that has matched no task and blocked nothing across the last 30 PRs the
registry records. Count that quiet window from the registry's loop log, not from
the file's dates; `date` and `last_refreshed` stay as CE metadata, not GC
counters. A retired file was fixed at the source or was never general: remove the
trap from the contract template, checklist, or gate it was promoted into, and
move the file to `docs/solutions/archived/` with its final date. The store must
stay small enough to grep and trust; a corpus that only grows rots into noise.

## The reviewer stays amnesic

Never load the store, or any learnings file, into a QA verifier's or reviewer's
context. The cross-vendor guarantee rests on two independent critics NOT sharing
priors; feed them a shared corpus and they correlate, which is the failure the
whole design exists to prevent. Learning reaches them only through the contract,
the standing checklist, and the gates, all shared inputs the implementer is
measured against too. The questions get smarter; the answers stay independent.
