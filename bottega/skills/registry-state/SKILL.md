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
  "verification": {                     // architect-verify writes evidence FILES + records paths
    "evidence_dir": "<abs>/.bottega/verify/<integration_head>",
    "source_mutation": "<path to mutmut output>",
    "dry": "<path to jscpd output>",
    "acceptance_mutation": "<path to gherkin-mutator output>",
    "verdict": "sign-off|bounce|null"   // pr-assemble refuses unless verdict==sign-off AND all 3 paths exist
  },
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
     "integrated_head": "<integration sha AFTER this slice merged>",  // set by integrate-wave
     "integration_gate": "pass|fail|unknown",  // integrate-wave's re-green result at integrated_head
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

Every slice is in exactly ONE `phase`, and phases are of two kinds — this is the ONE
rule the whole bundle uses:
- **Settled phases** (`pending`, `spec_done`, `coder_green`, `ready_to_integrate`,
  `contract_landed`, `integrated`, `done`) record the last COMPLETED-and-persisted fact
  — a role handback the coordinator verified, or a merge whose integration gate
  re-greened. A slice SETTLES only on such a fact, NEVER on a dispatch.
- **Running markers** (`specifying`, `coding`, `refactoring`) are transient: the
  coordinator sets one WHEN IT DISPATCHES a worker, purely to show the slice is in
  flight. A running marker is NEVER trusted on resume — it falls back to the last
  settled phase (see Resume).

So "settle a phase only on a completed fact" and "set a running marker on dispatch" are
the same rule from two sides. The wave loop (slice-wavefront) decides its next action
off the SETTLED phase, so a dispatch never fabricates progress.

| phase | kind | next action (off the SETTLED phase) | settles to / on what fact |
|-------|------|-------------------------------------|---------------------------|
| `pending` | settled | when every producer is `integrated`/`contract_landed`/`done`, dispatch the specifier (set marker `specifying`) | — |
| `specifying` | running marker | (in flight) | `spec_done` on the specifier's verified handback: `.feature` + generated FAILING entrypoint + glue committed, RED for the right reason; record `red_head`, `feature_file`, `acceptance_dir` |
| `spec_done` | settled | dispatch the coder (set marker `coding`) | — |
| `coding` | running marker | (in flight) | `coder_green` on the coder's verified handback: entrypoint + unit tests GREEN, committed; record `green_head` and `gate_results` |
| `coder_green` | settled | dispatch the refactorer (set marker `refactoring`) | — |
| `refactoring` | running marker | (in flight) | `ready_to_integrate` on the refactorer's verified handback: cleanup done, ALL gates green at a new `green_head`, `ready_for_next: yes` |
| `ready_to_integrate` | settled | hand to integrate-wave | `integrated` (or `contract_landed`) once integrate-wave merges AND re-greens the integration gate, recording `integrated_head` + `integration_gate: pass` |
| `contract_landed` | settled | wait on the follow-up impl slice | `integrated`/`done` once the FOLLOW-UP slice — the one whose `impl_followup_of` points at THIS spine — reaches `integrated` |
| `integrated` | settled | (none) | `done` when the whole DAG signs off |
| `done` | settled (terminal) | — | — |

A merge alone does NOT make a slice `integrated`: the phase advances only when
integrate-wave has ALSO re-greened the integration gate at the post-merge integration
head and recorded `integration_gate: pass`. A merged branch without that recorded
green evidence sits in the crash window and is handled by resume.

## The ready set (the ONE definition; slice-wavefront references this)
The **ready set** is the slices the wave loop ACTS ON, by the next-action column above
— it spans every non-terminal SETTLED phase, not just `pending`:
- `pending` with every producer `integrated`/`contract_landed`/`done` → dispatch specifier;
- `spec_done` → dispatch coder;
- `coder_green` → dispatch refactorer;
- `ready_to_integrate` → hand to integrate-wave (merge, not dispatch).
A running marker (`specifying`/`coding`/`refactoring`) is NOT in the ready set while a
worker is live; on resume it falls back to its last settled phase and re-enters the set
there. `integrated`, `contract_landed` (until its follow-up lands), and `done` are
EXCLUDED. Crucially, a settled phase is dispatchable from itself — so a crash AFTER a
handback but BEFORE the next dispatch (a slice sitting at `spec_done` or `coder_green`)
cannot stall: the next pass dispatches the next role. slice-wavefront calls this the
"integrate-or-dispatch" step and uses THIS definition; it does not restate it.

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
  1. **Merged WITH recorded green evidence?** A merged slice branch
     (`git branch --merged <integration-branch>`) is terminal (`integrated` / `done` /
     `contract_landed` per the spine rule) ONLY when the registry ALSO records green
     integration-gate evidence at its `integrated_head` (`integration_gate: pass`,
     persisted by integrate-wave when it re-greened after the merge). `git
     branch --merged` ALONE is never terminal — a crash can land between the merge and
     the post-merge re-green/persist. A branch that git shows merged but WITHOUT that
     recorded green evidence (no `integrated_head`/`integration_gate: pass`, or the
     persisted phase is still `ready_to_integrate`) sits in that crash window → enter
     RECOVERY: re-run the FULL gates at the current `integration_head`, and mark the
     slice `integrated` (recording `integrated_head` + `integration_gate: pass`) only
     once green; if red, route the failure per integrate-wave. Do not treat it as done.
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
