---
name: slice-wavefront
description: Load ONCE as the coordinator's orchestration loop after the DAG is approved. Land the spine, then drive dependency-ordered waves of parallel independent slices until the DAG drains, and finish with the architect verification.
---

# slice-wavefront — spine first, then dependency-ordered parallel waves

This is the coordinator's main loop after the plan gate. It walks the DAG from
the spine outward, running INDEPENDENT slices in parallel and serializing only
where a real edge demands it. The loop is RESUMABLE: its state lives in a durable
file, so an interrupted or crashed run picks up where it left off rather than
restarting.

## 0. Load or init the registry (resume, not restart)
The registry is DURABLE: it lives in a scratch file in the TARGET repo at
`.bottega/<feature-slug>.json`, not only in your context. On every (re)start, load
it or initialize it BEFORE touching branches or dispatching:
- If the scratch file is ABSENT, this is a fresh run. Initialize the registry with
  the approved plan/DAG + spine tags, and ensure the target repo IGNORES the
  scratch dir — add a `.bottega/` line to the target repo's `.gitignore` if it
  isn't already there. The `.bottega/` dir is runtime state (the registry plus the
  `.bottega/wt/<id>` worktrees), never part of the PR.
- If the scratch file is PRESENT, a prior run was interrupted. RECONCILE it
  against git ground truth before doing anything else:
    - the integration branch's real HEAD (`git rev-parse`),
    - which `slice/*` branches and `.bottega/wt/<id>` worktrees actually exist,
    - which slices are already merged into the integration branch
      (`git branch --merged <integration-branch>` / `git log`).
  Rewrite each slice's status from what git actually shows (a slice whose branch is
  already merged is `merged`/`done`; one whose branch exists but isn't merged is
  in-flight; one with no branch is back in `pending`), then RESUME the wave loop
  from the recomputed ready set — never restart from zero.
- Reconcile stale worktrees/branches left by the dead run: REUSE a worktree/branch
  whose commit matches the registry's recorded SHA; REBUILD it (remove the
  worktree, re-add it off the current integration HEAD) when its commit has drifted
  or its worktree is missing. A slice recorded in-flight whose branch never
  received a commit returns to the ready set for a fresh dispatch.

## Persist after every transition
The registry is the team's long-horizon memory; you write no code and must not
hold build state only in your own context. WRITE `.bottega/<feature-slug>.json`
after EVERY state transition — a slice dispatched, a wave integrated, a slice
merged, a bounce routed, the architect's sign-off — so any restart recovers by
re-reading it. Each slice entry carries its {session conversation_id, worktree,
branch, base SHA, status, changed_files, handbacks[]} alongside the plan/DAG +
spine tags (the coordinator's registry schema). For recovery, a transition that
wasn't persisted didn't happen — persist it before you end the turn.

## 1. Create or adopt the integration branch
One branch carries the whole feature. On a fresh run, branch it off the agreed
base commit and record it as the integration branch + integration HEAD in the
registry; on a resume, ADOPT the existing branch at its reconciled HEAD rather
than recreating it. Every wave branches its slice worktrees off the CURRENT
integration HEAD.

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
  diff. Record each dispatch's `conversation_id` + title in the registry and
  PERSIST before ending the turn.
- **Wait** for the wave's sessions to finish (the inbox wakes you; never
  busy-poll).
- **Call integrate-wave** to dup-scan, merge each `slice/*` branch into the
  integration branch one at a time, and re-green the gates. This advances the
  integration HEAD. Record each slice's `merged` status + `changed_files` and the
  new integration HEAD, and PERSIST.
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
