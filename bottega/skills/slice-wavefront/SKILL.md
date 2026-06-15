---
name: slice-wavefront
description: Load ONCE as the coordinator's orchestration loop after the DAG is approved. Land the spine, then drive dependency-ordered waves of parallel independent slices until the DAG drains, and finish with the architect verification.
---

# slice-wavefront — spine first, then dependency-ordered parallel waves

This is the coordinator's main loop after the plan gate. It walks the DAG from
the spine outward, running INDEPENDENT slices in parallel and serializing only
where a real edge demands it.

## 1. Create the integration branch
One branch carries the whole feature. Branch it off the agreed base commit and
record it as the integration branch + integration HEAD in the registry. Every
wave branches its slice worktrees off the CURRENT integration HEAD.

## 2. Spine first (sequential)
Land the spine slices onto the integration branch ONE at a time, before any wave.
A spine slice can be landed as a thin CONTRACT slice — just the
interface / signature / stub / migration — so that dependents can compile and
their specifier can author failing tests against a real contract while the full
implementation proceeds in parallel later. Re-green the gates after each spine
landing; advance the integration HEAD.

## 3. The wave loop
Repeat until the DAG drains:
- **Ready set** = every not-yet-done slice whose producers are ALL merged into
  the integration branch.
- **Spin a worktree per ready slice off the current integration HEAD**, up to the
  width the coordinator's policy allows (`git -C <target> worktree add
  .bottega/wt/<id> -b slice/<id> <integration-HEAD-sha>`). Record each slice's
  worktree path, branch, and base SHA in the registry, and confirm
  `git -C <wt> rev-parse HEAD` equals the recorded integration HEAD.
- **Dispatch fresh sessions K-wide in parallel**, one per ready slice, each
  running **run-slice-pipeline** for its slice. Each session gets only its
  slice's handoff packet (see run-slice-pipeline) — never a sibling's session or
  diff. Record each dispatch's `conversation_id` + title.
- **Wait** for the wave's sessions to finish (the inbox wakes you; never
  busy-poll).
- **Call integrate-wave** to dup-scan, merge each `slice/*` branch into the
  integration branch one at a time, and re-green the gates. This advances the
  integration HEAD.
- **Recompute the ready set** off the fresh HEAD and loop.

## 4. Finish
When the DAG has drained — every slice merged into the integration branch — call
**architect-verify** for the final whole-feature join.

## The parallel-dispatch primitive (inlined here)
Spin K worktrees off one base SHA, run K fresh sessions in parallel, collect their
handbacks. That is the whole primitive, and it lives here — there is no separate
fan-out skill to borrow it from.

## Invariants
- Fresh session ACROSS slices; the same session is only ever continued for
  feedback on the SAME slice it already owns.
- Parallel only across INDEPENDENT slices — slices with NO edge either way. An
  edge always serializes; `touches` overlap never does (it is a merge cost
  integrate-wave handles).
- A degenerate DAG — a pure chain where each slice consumes the previous — yields
  one ready slice per wave, which is exactly the sequential loop. Width is an
  upper bound, not a target.
