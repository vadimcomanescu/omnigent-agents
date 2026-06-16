---
name: registry-state
description: The single home for the coordinator's registry schema and the per-slice phase state machine. Load alongside slice-wavefront. Defines every slice phase (pending → specifying → spec_done → coding → coder_green → refactoring → ready_to_integrate → integrated → done, plus contract_landed for spine stubs), how each advances, the contract-landed spine rule, and how RESUME reclassifies a slice from its PERSISTED phase + git ground truth + gate results — never from mere commit existence.
---

# registry-state — the registry schema and the slice phase machine

The registry is the team's durable, restorable memory. The coordinator writes no
code, so this file is the single source of truth for build state; it is PERSISTED to
`<target>/.bottega/<slug>.json` with the coordinator's `sys_os_*` tools and must
survive a crash or restart. slice-wavefront, run-slice-pipeline, integrate-wave, and
architect-verify all read and advance the state defined here.

## The registry schema

```jsonc
{
  "slug": "...", "integration_branch": "bottega/<slug>",
  "target_repo": "<abs path>", "stack": "python|typescript",
  "gates": {"test": "...", "lint": "...", "typecheck": "...", "coverage": "..."},
  "aps": {                              // resolved from .bottega/aps.lock at BOOTSTRAP
    "parser": "<abs>/.bottega/bin/gherkin-parser",
    "mutator": "<abs>/.bottega/bin/gherkin-mutator",
    "venv": "<abs>/.bottega/aps-venv",
    "generator": "<abs>/.bottega/aps-venv/bin/acceptance-entrypoint-generator",
    "adapter": "<abs>/.bottega/aps-venv/bin/aps-adapter"
  },
  "base_commit": "<sha>", "integration_head": "<sha>",
  "bounce_round": <int>,
  "slices": [
    {"id": "...", "behavior": "...",
     "produces": [...], "consumes": [...], "touches": [...],
     "spine": <bool>,
     "contract_only": <bool>,            // spine landed as a stub/interface/migration
     "impl_followup_of": "<spine slice id>|null",  // set on the follow-up impl slice
     "depends_on": ["<slice id>", ...],  // derived: B.consumes ∩ A.produces
     "phase": "pending|specifying|spec_done|coding|coder_green|refactoring|ready_to_integrate|contract_landed|integrated|done",
     "worktree": "<abs path>", "branch": "slice/<id>",
     "base_sha": "<integration HEAD it branched from>",
     "feature_file": "features/<id>.feature",      // APS Gherkin the specifier authored
     "acceptance_dir": "acceptance/generated/<id>", // generated entrypoint dir
     "red_head": "<sha of the specifier's committed FAILING acceptance>",
     "green_head": "<sha of the last commit where this slice's gates were GREEN>",
     "gate_results": {"at_sha": "<sha>", "test": "pass|fail|unknown",
                      "lint": "...", "typecheck": "...", "coverage": "..."},
     "last_handback": {"role": "specifier|coder|refactorer|architect",
                       "head": "<sha>", "changed_files": "<git diff --stat>",
                       "ready_for_next": <bool>},
     "sessions": {"specifier": {"title": "...", "conversation_id": "..."},
                  "coder":     {"title": "...", "conversation_id": "..."},
                  "refactorer":{"title": "...", "conversation_id": "..."}},
     "handbacks": [{"role": "...", "head": "<sha>", "changed_files": "<diff --stat>"}]}
  ]
}
```

`sessions` holds ONE conversation per role for this slice. Reuse the RELEVANT role's
`conversation_id` for feedback on that role's work (the coder for an implementation
fix, the refactorer for a cleanup fix); only a NEW slice gets fresh per-role
titles/sessions. `bounce_round` is the architect bounce counter (architect-verify
caps it).

## The per-slice phase machine

Every slice is in exactly ONE `phase`. A phase advances ONLY on a completed-and-
recorded fact (a role handback the coordinator verified, or a merge), never on a
dispatch. The running phases (`specifying`, `coding`, `refactoring`) are live-run
states only — on resume they are NOT trusted (see below).

| phase | meaning | advances to | on what fact |
|-------|---------|-------------|--------------|
| `pending` | a producer is not yet `integrated`/`done` | `specifying` | all producers integrated → slice enters the ready set, specifier dispatched |
| `specifying` | specifier running | `spec_done` | specifier handback: `.feature` + generated FAILING acceptance entrypoint committed, confirmed RED for the right reason; record `red_head`, `feature_file`, `acceptance_dir` |
| `spec_done` | the RED acceptance is committed; no implementation yet | `coding` | coder dispatched |
| `coding` | coder running | `coder_green` | coder handback: acceptance entrypoint + unit tests GREEN, committed; record `green_head` and `gate_results` |
| `coder_green` | implementation is green; not yet cleaned | `refactoring` | refactorer dispatched |
| `refactoring` | refactorer running | `ready_to_integrate` | refactorer handback: structure-preserving cleanup, ALL gates green at a new `green_head`, `ready_for_next: yes` |
| `ready_to_integrate` | gates green + refactorer handback present | `integrated` (or `contract_landed`) | integrate-wave merges the branch into the integration branch and re-greens |
| `contract_landed` | a spine STUB merged so dependents can build; full impl still owed | `integrated`/`done` | its `impl_followup_of` slice reaches `integrated` |
| `integrated` | branch merged into the integration branch | `done` | whole DAG signs off |
| `done` | terminal | — | — |

A slice is in the **ready set** for (re)dispatch only when every producer is
`integrated`/`done` AND its phase is `pending` or a running phase that resume kicked
back to a not-yet-handed-back state. `integrated`, `contract_landed`, and the
post-handback phases are EXCLUDED — a slice that already holds a commit is never
re-dispatched from scratch.

## The spine contract-landed rule (1.2)

A spine slice may land as a thin CONTRACT — just the interface/signature/stub/
migration — so dependents can compile and their specifier can author failing tests
against a REAL contract while the full implementation proceeds later. When a spine
slice is landed as a stub:
- set `contract_only: true` and, when it merges, move it to `contract_landed` (NOT
  `done`) — its CONTRACT is landed but its behavior is not yet implemented;
- a dependent becomes ready when its producers' CONTRACTS are landed
  (`contract_landed` counts as "producer satisfied" for unblocking dependents), so
  the wave can proceed;
- create a separate follow-up implementation slice with `impl_followup_of` set to the
  spine slice id, tracked through the normal phases until it reaches `integrated`;
- only THEN does the spine slice flip from `contract_landed` to `done`. A
  `contract_landed` spine with an unfinished follow-up is NOT done, and the run does
  not finish while any such follow-up is open.

## Persist after every transition

WRITE `.bottega/<slug>.json` after EVERY phase transition — slice dispatched, role
handback recorded, wave merged, bounce routed, architect sign-off — before you end
the turn. For recovery, a transition you did not persist did not happen. Write it
atomically (temp file then move) so a crash never leaves a half-written registry.

## Resume — reclassify from phase + git + gate, never from a bare commit

On (re)start, LOAD-OR-INIT before touching branches or dispatching:
- **Absent file → fresh run.** Initialize from the planned DAG (slices, edges, spine
  tags, all `pending`), and ensure the target repo gitignores the runtime scratch
  while TRACKING the lock — add `.bottega/*` and `!.bottega/aps.lock` to the target's
  `.gitignore` (NOT a blanket `.bottega/`, which can't re-include the committed lock).
- **Present file → a prior run was interrupted.** Do NOT trust a recorded RUNNING
  phase, and NEVER classify by mere commit existence. For each slice, reconcile its
  PERSISTED phase against git ground truth and the recorded gate result:
  1. **Merged?** If the slice branch is merged into the integration branch
     (`git branch --merged <integration-branch>`) → `integrated` (or `done`/
     `contract_landed` per the spine rule). Terminal for re-dispatch.
  2. **Running phase?** `specifying`/`coding`/`refactoring` are never trusted on
     resume — the session may be dead. Reclassify to the last COMPLETED phase from
     git + gates: a `coding` slice with no commit past `red_head` falls back to
     `spec_done` (re-dispatch the coder); a `coding`/`refactoring` slice whose
     recorded `gate_results.at_sha` is green at the branch HEAD falls back to
     `coder_green` (dispatch the refactorer).
  3. **`spec_done` has ONLY the specifier's RED commit.** A branch that carries just
     `red_head` (the failing acceptance) is `spec_done`, NOT ready to integrate — it
     MUST be sent to the coder, never to integrate-wave. This is the rule that mere-
     commit classification gets wrong: a red-only branch is not a finished slice.
  4. **`ready_to_integrate` only when proven.** A slice reaches `ready_to_integrate`
     only with a refactorer handback AND gates green at its `green_head`. If the
     persisted phase claims `ready_to_integrate` but the gates are not green at the
     recorded `green_head`, kick it back to `coder_green` (or `coding`) and re-verify
     — do not feed it to integrate-wave.
  5. **Blocked?** A producer not yet `integrated`/`contract_landed` → `pending`.
- **Reconcile worktrees/branches.** REUSE a worktree/branch whose commit matches the
  recorded sha; REBUILD it (remove the worktree, re-add it off the current
  integration HEAD) when its commit drifted or its worktree is missing. A slice with
  a committed branch keeps its reclassified phase; only a slice with no commit past
  its base returns toward the ready set.

Write the reclassified phases back, PERSIST, then RESUME the wavefront from the
recomputed ready set — never restart from zero, never re-dispatch a slice that
already holds the relevant commit.

## The integrate gate (enforced in integrate-wave)

integrate-wave merges ONLY slices in `ready_to_integrate`. Anything in any other
phase — `spec_done` (red only), `coder_green` (not yet cleaned), a running phase, or
a stale `ready_to_integrate` whose gates are not actually green — is REJECTED and
routed back to the role that owns the next step, never merged.
