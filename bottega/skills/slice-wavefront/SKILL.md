---
name: slice-wavefront
description: Load ONCE as the coordinator's orchestration loop after the DAG is built. Land the spine, then drive dependency-ordered waves of parallel independent slices until the DAG drains, and finish with the architect verification.
---

# slice-wavefront — spine first, then dependency-ordered parallel waves

This is the coordinator's main loop once the DAG is built. It walks the DAG from
the spine outward, running INDEPENDENT slices in parallel and serializing only
where a real edge demands it. The loop is RESUMABLE: its state lives in a durable
file, so an interrupted or crashed run picks up where it left off rather than
restarting.

## Slice states (one model — the resume step and the ready set share it)
Every slice is in exactly ONE state, decided from GIT ground truth, not from trust
in the recorded status. Both the resume step (0) and the wave loop (3) use these
exact definitions, so a slice can never be double-dispatched or left stuck with no
integration path:
- **DONE** — the slice's commit is merged into the integration branch
  (`git branch --merged <integration-branch>`). Terminal; EXCLUDED from the ready
  set; never re-dispatched. (registry `status: merged`, then `done` once the whole
  DAG signs off.)
- **AWAITING-INTEGRATION** — `slice/<id>` has a worker commit that is NOT yet in
  the integration branch. It goes STRAIGHT to integrate-wave to be merged; it is
  NOT in the ready set and is NEVER re-dispatched. (registry
  `status: awaiting-integration`.)
- **READY** — every producer is DONE and the slice has NO commit yet (its branch
  is missing, or its worktree/branch exists with no commit on it). It is in the
  READY SET for (re)dispatch; rebuild a drifted or empty worktree off the current
  integration HEAD first. (registry `status: ready`.)
- **PENDING** — a producer is not yet DONE. Blocked; not in the ready set until its
  producers merge. (registry `status: pending`.)
- **IN-FLIGHT** — dispatched and running in a live role-session, no commit yet. A
  live-run state only; on RESUME it is NOT trusted — reclassify from git: a commit
  on the branch -> AWAITING-INTEGRATION, otherwise -> READY. (registry
  `status: in-flight`.)

## 0. Load or init the registry (resume, not restart)
The registry is DURABLE: it lives in a scratch file in the TARGET repo at
`.bottega/<feature-slug>.json`, not only in your context. On every (re)start, load
it or initialize it BEFORE touching branches or dispatching:
- If the scratch file is ABSENT, this is a fresh run. Initialize the registry with
  the planned DAG + spine tags, and ensure the target repo IGNORES the
  scratch dir — add a `.bottega/` line to the target repo's `.gitignore` if it
  isn't already there. The `.bottega/` dir is runtime state (the registry plus the
  `.bottega/wt/<id>` worktrees), never part of the PR.
- If the scratch file is PRESENT, a prior run was interrupted. Do NOT trust the
  recorded statuses — RECLASSIFY every slice from git ground truth using the slice
  state model above. Read:
    - the integration branch's real HEAD (`git rev-parse`),
    - which `slice/*` branches and `.bottega/wt/<id>` worktrees actually exist and
      whether each branch carries a commit past its base SHA,
    - which slices are already merged into the integration branch
      (`git branch --merged <integration-branch>` / `git log`).
  Map each slice to exactly one state: merged -> DONE; a commit on `slice/<id>`
  not yet merged -> AWAITING-INTEGRATION; producers all DONE but no commit
  (branch missing, or worktree/branch present with no commit) -> READY; a producer
  not yet DONE -> PENDING. Write the reclassified statuses back, then RESUME the
  wave loop — never restart from zero, and never re-dispatch a slice that already
  has a commit.
- Reconcile stale worktrees/branches left by the dead run: REUSE a worktree/branch
  whose commit matches the registry's recorded SHA; REBUILD it (remove the
  worktree, re-add it off the current integration HEAD) when its commit has drifted
  or its worktree is missing. A slice with a committed branch stays
  AWAITING-INTEGRATION (it is integrated, not re-dispatched); only a slice with no
  commit returns to READY.

## Persist after every transition
The registry is the team's long-horizon memory; you write no code and must not
hold build state only in your own context. WRITE `.bottega/<feature-slug>.json`
after EVERY state transition — a slice dispatched, a wave integrated, a slice
merged, a bounce routed, the architect's sign-off — so any restart recovers by
re-reading it. Each slice entry carries its {per-role session conversation_ids
(specifier / coder / refactorer), worktree, branch, base SHA, status,
changed_files, handbacks[]} alongside the plan/DAG + spine tags (the coordinator's
registry schema). For recovery, a transition that
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
Repeat until the DAG drains. Each pass starts by CLASSIFYING every not-DONE slice
with the slice state model above, then:
- **Integrate first.** Any AWAITING-INTEGRATION slice — a committed `slice/*`
  branch not yet merged, e.g. one that finished just before a crash — goes
  STRAIGHT to **integrate-wave**; it is NOT spun up or re-dispatched.
- **Ready set** = every READY slice: producers ALL merged into the integration
  branch (DONE) and no commit on its branch yet. DONE, AWAITING-INTEGRATION,
  IN-FLIGHT, and PENDING slices are EXCLUDED from the ready set — so a slice with a
  commit is never re-dispatched and a blocked slice never runs early.
- **Spin a worktree per ready slice off the current integration HEAD**, up to the
  width the coordinator's policy allows (`git -C <target> worktree add
  .bottega/wt/<id> -b slice/<id> <integration-HEAD-sha>`). Record each slice's
  worktree path, branch, and base SHA in the registry, and confirm
  `git -C <wt> rev-parse HEAD` equals the recorded integration HEAD.
- **Run K slices' pipelines in parallel** — one **run-slice-pipeline** per ready
  slice, up to K. This does NOT mean one worker session runs all three roles: a
  slice's run-slice-pipeline is the COORDINATOR's 3-role dispatch SEQUENCE for that
  slice — specifier, then coder, then refactorer, each a SEPARATE session, with a
  handback to you between each (see run-slice-pipeline). The K-parallelism is ACROSS
  slices (K slices' pipelines advancing at once), never multiple roles in one
  session. Each session gets only its slice's handoff packet — never a sibling's
  session or diff. Mark each in-flight slice IN-FLIGHT, record its PER-ROLE
  `conversation_id`s + titles as each role is dispatched, and PERSIST before ending
  the turn.
- **Wait** for the wave's sessions to finish (the inbox wakes you; never
  busy-poll). A slice that hands back a commit becomes AWAITING-INTEGRATION.
- **Call integrate-wave** to dup-scan, merge each AWAITING-INTEGRATION `slice/*`
  branch into the integration branch one at a time, and re-green the gates. This
  advances the integration HEAD. Mark each merged slice DONE, record its
  `changed_files` and the new integration HEAD, and PERSIST.
- **Recompute** off the fresh HEAD and loop.

## 4. Finish
When the DAG has drained — every slice merged into the integration branch — call
**architect-verify** for the final whole-feature join.

## The parallel-dispatch primitive (inlined here)
Spin K worktrees off one base SHA, run K fresh sessions in parallel, collect their
handbacks. That is the whole primitive, and it lives here — there is no separate
fan-out skill to borrow it from.

## Invariants
- Fresh role-sessions ACROSS slices; a role-session is only ever continued for
  feedback on the SAME slice + SAME role it already owns. One session never spans
  specifier + coder + refactorer — those are three separate sessions per slice.
- Parallel only across INDEPENDENT slices — slices with NO edge either way. An
  edge always serializes; `touches` overlap never does (it is a merge cost
  integrate-wave handles).
- A degenerate DAG — a pure chain where each slice consumes the previous — yields
  one ready slice per wave, which is exactly the sequential loop. Width is an
  upper bound, not a target.
