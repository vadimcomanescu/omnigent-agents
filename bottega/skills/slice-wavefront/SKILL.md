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

## 1. Create or adopt the integration branch, then COMMIT THE LOCK onto it
One branch carries the whole feature: `bottega/<slug>`. Fresh run: branch it off the
agreed base commit and record it + the integration HEAD. Resume: ADOPT the existing
branch at its reconciled HEAD. Every wave branches its slice worktrees off the CURRENT
integration HEAD (via fanout).

The integration branch is the branch pr-assemble pushes, so the APS lock BOOTSTRAP
wrote must be committed ONTO it (else it is absent from a fresh clone and the
"pinned/reproducible" claim is false). As the FIRST commit on a fresh integration
branch, stage and commit the lock from the target root:
```sh
git -C "$TARGET_ROOT" add -f .bottega/aps.lock          # tracked despite the .bottega/* ignore
git -C "$TARGET_ROOT" commit -m "bottega: pin APS toolchain (.bottega/aps.lock)"
```
Confirm `git -C "$TARGET_ROOT" ls-files --error-unmatch .bottega/aps.lock` succeeds
before any wave. pr-assemble re-checks this before opening the PR.

## 2. Spine first (sequential)
Land the spine slices onto the integration branch ONE at a time, before any wave. A
spine slice may land as a thin CONTRACT — interface / signature / stub / migration —
so dependents can compile and their specifier can author failing tests against a REAL
contract. Per registry-state's contract-landed rule: a contract stub that merges goes
to `contract_landed` (not `done`), unblocks its dependents, and keeps a tracked
follow-up implementation slice until it reaches `integrated`. Re-green the gates after
each spine landing; advance the integration HEAD.

## 3. The wave loop — integrate-or-dispatch
Repeat until the DAG drains. Each pass:
- **Classify** every not-`done` slice by its SETTLED phase (registry-state). A running
  marker left by a dead run falls back to its last settled phase first.
- **Integrate-or-dispatch off the ready set.** Use registry-state's ONE ready-set
  definition — do not restate it. For each slice in it, take its next action:
  `ready_to_integrate` → hand to **integrate-wave** (merge, never re-dispatch);
  otherwise ENTER **run-slice-pipeline at the role matching the slice's settled phase** —
  `pending` → specifier, `spec_done` → coder, `coder_green` → refactorer — running
  FORWARD from there and NEVER re-running a completed role. Because each settled phase
  enters at its OWN next role, a slice stranded at `spec_done`/`coder_green` by a crash
  resumes at the coder/refactorer (not back at the specifier) — the run cannot stall
  after a handback, and no committed spec/implementation is re-done.
- **Fan out the dispatches.** Call **fanout** for the slices being dispatched, up to K:
  it spins one worktree per slice off the current integration HEAD and ENTERS each
  slice's **run-slice-pipeline** at that slice's phase-appropriate role (the pipeline is
  phase-aware; the roles remain SEPARATE sessions with a handback between each). The
  K-parallelism is ACROSS slices, never multiple roles in one session. fanout sets each
  slice's running marker + the dispatched role's `conversation_id` and PERSISTS before
  the turn ends.
- **Collect.** Each verified handback SETTLES the slice to the next phase (per
  registry-state); a slice that finishes its pipeline settles at `ready_to_integrate`.
- **Integrate the wave.** **integrate-wave** dup-scans, merges each
  `ready_to_integrate` `slice/*` one at a time, re-greens, and records `integrated_head`
  + `integration_gate: pass`. It REJECTS anything not `ready_to_integrate`. This
  advances the integration HEAD; PERSIST.
- **Recompute** off the fresh HEAD and loop.

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
