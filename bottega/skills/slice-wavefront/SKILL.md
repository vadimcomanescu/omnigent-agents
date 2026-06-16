---
name: slice-wavefront
description: Load ONCE as the coordinator's BUILD loop after the DAG is built. Land the spine, then drive dependency-ordered waves of independent slices to ready_to_integrate and merge each wave, until the DAG drains — then hand to architect-verify. Holds the width policy; reads the slice phase machine + registry schema from registry-state, fans out parallel dispatch through fanout, runs each slice through run-slice-pipeline, and integrates each wave through integrate-wave.
---

# slice-wavefront — spine first, then dependency-ordered parallel waves

The coordinator's main BUILD loop once the DAG is built. It walks the DAG from the
spine outward, running INDEPENDENT slices in parallel and serializing only where a
real edge demands it. The loop is RESUMABLE: its state lives in the durable registry,
so an interrupted run picks up where it left off.

This skill owns the WAVE LOOP and the WIDTH POLICY. The slice phase machine
(`pending → specifying → spec_done → coding → coder_green → refactoring →
ready_to_integrate → integrated/done`, plus `contract_landed`), the registry schema,
the persist-after-every-transition rule, and the resume reclassification all live in
**registry-state** — load it alongside this skill and use its definitions; do not
restate them here. The parallel-dispatch mechanics live in **fanout**.

## Width policy
Default CONSERVATIVE. Per wave, K = the number of INDEPENDENT ready slices run in
parallel (slices with no DAG edge either way), capped at ~5. A degenerate DAG — a
pure chain where each slice consumes the previous — collapses to K=1, the sequential
loop. Widen only across truly independent slices; file overlap (`touches`) is a merge
cost integrate-wave handles, never a reason to widen or to serialize. Width is an
upper bound, not a target.

## 0. Load or init the registry (resume, not restart)
Per registry-state's LOAD-OR-INIT: absent file → fresh run (init from the planned DAG;
ignore the runtime scratch, track the lock); present file → reclassify every slice
from its persisted phase + git ground truth + gate result and RESUME. Never restart
from zero; never re-dispatch a slice that already holds the relevant commit.

## 1. Create or adopt the integration branch
One branch carries the whole feature: `bottega/<slug>`. Fresh run: branch it off the
agreed base commit and record it + the integration HEAD. Resume: ADOPT the existing
branch at its reconciled HEAD. Every wave branches its slice worktrees off the CURRENT
integration HEAD (via fanout).

## 2. Spine first (sequential)
Land the spine slices onto the integration branch ONE at a time, before any wave. A
spine slice may land as a thin CONTRACT — interface / signature / stub / migration —
so dependents can compile and their specifier can author failing tests against a REAL
contract. Per registry-state's contract-landed rule: a contract stub that merges goes
to `contract_landed` (not `done`), unblocks its dependents, and keeps a tracked
follow-up implementation slice until it reaches `integrated`. Re-green the gates after
each spine landing; advance the integration HEAD.

## 3. The wave loop
Repeat until the DAG drains. Each pass:
- **Classify** every not-`done` slice from registry-state's phase machine.
- **Integrate first.** Any slice in `ready_to_integrate` (a finished slice, e.g. one
  that completed just before a crash) goes STRAIGHT to **integrate-wave**; it is NOT
  re-dispatched.
- **Ready set** = every slice whose producers are all `integrated`/`contract_landed`
  and whose phase is `pending` (or a running phase that resume kicked back). Excludes
  `ready_to_integrate`, `integrated`, `contract_landed`, and the post-handback phases.
- **Fan out the wave.** Call **fanout** for the ready set up to K: it spins one
  worktree per ready slice off the current integration HEAD, then runs each slice's
  **run-slice-pipeline** — the coordinator's 3-role dispatch SEQUENCE (specifier →
  coder → refactorer, SEPARATE sessions, a handback between each). The K-parallelism
  is ACROSS slices (K slices' pipelines advancing at once), never multiple roles in
  one session. fanout records each slice's phase + per-role `conversation_id`s and
  PERSISTS before the turn ends.
- **Collect.** Each slice that finishes its pipeline reaches `ready_to_integrate`
  (refactorer handback + gates green at its `green_head`).
- **Integrate the wave.** Call **integrate-wave** to dup-scan, merge each
  `ready_to_integrate` slice into the integration branch one at a time, and re-green
  the gates. It REJECTS anything not `ready_to_integrate`. This advances the
  integration HEAD; mark each merged slice `integrated` and PERSIST.
- **Recompute** the ready set off the fresh HEAD and loop.

## 4. Finish
When the DAG has drained — every slice `integrated`/`done`, no `contract_landed` spine
with an open implementation follow-up — call **architect-verify** for the final
whole-feature join.

## Invariants
- Fresh role-sessions ACROSS slices; a role-session is only ever continued for
  feedback on the SAME slice + SAME role. One session never spans specifier + coder +
  refactorer — three separate sessions per slice.
- Parallel only across INDEPENDENT slices (no edge either way). An edge always
  serializes; `touches` overlap never does.
