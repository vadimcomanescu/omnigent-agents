---
name: run-slice-pipeline
description: Load per slice — the COORDINATOR's 3-role dispatch sequence (specifier → coder → refactorer, SEPARATE sessions, a handback to the coordinator between each) that drives ONE vertical slice from a generated FAILING acceptance entrypoint to refactored green in one worktree. Holds the dispatch-packet contract and the APS commands each role runs. Load for every slice the wavefront dispatches.
---

# run-slice-pipeline — one slice, one worktree, the whole way to green

The slice is the unit of delegation. This is the role sequence for ONE slice, in ONE
worktree. The COORDINATOR runs it as THREE SEPARATE role-sessions in sequence,
staying in control between each: dispatch the specifier, wait for the handback,
dispatch the coder, wait, dispatch the refactorer. The three roles are different
agents on different harnesses — so they are DIFFERENT sessions; one session NEVER runs
the whole specifier → coder → refactorer pipeline.

## The sequence (the coordinator dispatches each, in order; phases per registry-state)
1. **specifier** (session A) authors THIS slice's Gherkin `.feature`, GENERATES its
   FAILING acceptance entrypoint with the APS kit (parser → generator), AND authors the
   step-handler glue (see below), confirming it fails for the right reason. Hands back →
   slice goes `specifying` → `spec_done` (`red_head` recorded). APS acceptance is a layer
   ON TOP of unit tests, not instead.
2. **coder** (session B) TDD-implements the ENTIRE slice in ONE persistent session
   (see the one-session rule below): drives the generated acceptance entrypoint and
   its native unit tests red → green, committing on green. Hands back → `coding` →
   `coder_green` (`green_head` + `gate_results` recorded).
3. **refactorer** (session C) does structure-preserving cleanup and drives lint /
   typecheck / coverage green and adds property tests where they pay; no new behavior,
   the acceptance + unit tests still pass unchanged. Hands back → `refactoring` →
   `ready_to_integrate`.

## The coder's one-session inner loop (stated ONCE, here)
The red → green → refactor micro-loop is the CODER's alone, inside the coder's ONE
persistent session: write a small failing unit test, write the minimum code to pass
it, clean up on green, repeat — until the generated acceptance entrypoint and the unit
tests all pass. The coder NEVER carves the slice into sub-tasks farmed to fresh
sessions and NEVER starts a fresh session per micro-step. This one-session rule is the
coder's only — the specifier and refactorer are their own single sessions; it is NOT
restated in any role prompt.

## The APS pipeline the slice runs (real kit commands, Python/pytest)
The coordinator threads the BOOTSTRAP-resolved ABSOLUTE paths into every packet:
`APS_PARSER` (gherkin-parser), `APS_VENV` (the pinned 3.12 venv — it has `aps_kit`,
`mutmut`, AND pytest, pulled in transitively by mutmut), `APS_GENERATOR`
(`acceptance-entrypoint-generator`), `APS_ADAPTER` (`aps-adapter`), `APS_MUTATOR`
(gherkin-mutator). Per slice, the specifier authors and the coder drives:
```sh
"$APS_PARSER" features/<id>.feature build/<id>.ir.json
APS_FEATURE_PATH=features/<id>.feature \
  "$APS_GENERATOR" build/<id>.ir.json acceptance/generated/<id>
"$APS_VENV/bin/pytest" acceptance/generated/<id> -q
```
The generated tests must import BOTH `aps_kit` AND the project's system-under-test, so
run them with the venv's pytest (it has `aps_kit`) and make the project importable to
that pytest WITHOUT prepending the venv's whole site-packages to `PYTHONPATH` — that
would shadow the project's own dependency versions. The clean way: the conftest inserts
the project's source dir onto `sys.path` (a zero-dep, non-shadowing add), and a project
that has third-party deps is `pip install`-ed into the venv. (`APS_MUTATOR` +
`APS_ADAPTER` are the architect's acceptance-mutation gate, run once over the WHOLE
feature set in architect-verify — `gherkin-mutator` drives the same pytest via
`$APS_VENV/bin/aps-adapter pytest ...` — not per slice.) This path is Python/pytest
only; no other stack is wired.

## The step-handler glue (the specifier authors it — load-bearing)
`aps_kit.default_registry` starts EMPTY, so a freshly generated acceptance test reds
with `UnsupportedStepError` (a HARNESS gap, not the behavior) until handlers register.
AND it is a global SINGLETON whose `.step()` raises `ValueError("duplicate step
handler")` on a repeated step text, while bare pytest auto-loads EVERY generated
`conftest.py` — so two features sharing any step text (e.g. `a calculator`) would error
the whole gate at collection. So AFTER parser → generator, the specifier authors a
slice-scoped `conftest.py` in the generated acceptance dir (`acceptance/generated/<id>`)
that:
- builds a PER-FEATURE `Registry()` — NEVER `default_registry` — and routes the
  generated test to it with an autouse fixture
  (`monkeypatch.setattr(aps_kit.runtime, "default_registry", registry)`). The generated
  test calls `run_execution(ir, s, e)` with no registry arg, so this is what isolates
  features that share step text. NO kit change is needed: `run_execution` already
  accepts a per-feature `registry`. (`examples/aps-step-isolation` is the runnable
  regression for this.)
- registers a handler for EACH Gherkin step keyed by its EXACT IR `text` — placeholders
  and all (`I subtract <b> from <a>`), from the parsed IR JSON, NOT the raw `.feature`;
- binds the When-step to a REAL call into the system-under-test (e.g.
  `world["calc"].subtract(int(ex["a"]), int(ex["b"]))`) so the test reds for the RIGHT
  reason — behavior absent → `AttributeError` — and greens on the obvious implementation
  the coder writes;
- reads each example / expected VALUE FROM THE IR example row `ex`, NEVER hardcoded.
  Load-bearing: `gherkin-mutator` mutates the example cells, so a handler that hardcoded
  values would let mutants survive (vacuous acceptance). Reading from `ex` is what kills
  them.
The derived `build/<id>.ir.json` is a gitignored intermediate, regenerated per run (the
specifier adds `build/` to the target `.gitignore`). The specifier's committed
deliverable is the `.feature` + the generated entrypoint + the `conftest.py` glue, RED
for the right reason — never the slice implementation (that is the coder's).

## The dispatch-packet contract (what a worker is handed, and only this)
Each `sys_session_send` for a slice carries ONLY:
- `title`: short and slice-specific, naming the work not the vendor
  (`slice-2-coder-empty-cart`). A NEW slice/role gets a fresh title (clean session);
  reuse a title / `session_id` ONLY to continue feedback on the SAME slice + SAME role.
- `args.purpose`: `implement` for specifier/coder/refactorer, `review` for the
  architect, `explore` for read-only recon. Nothing else.
- `args.input`: the slice-scoped packet — the slice id + behavior spec, the contract
  (`produces`/`consumes`/`touches`), the ABSOLUTE worktree path (cd there first), the
  slice branch `slice/<id>` + base SHA, the gate commands, the resolved APS paths
  above, and the done definition (acceptance entrypoint + unit tests green; gates
  green). NEVER another slice's session or diff.
Demand a CHANGED-FILES `git diff --stat` in every handback; if one is missing, ask
before advancing. A worker that needs merged sibling code reads it from its OWN
worktree (branched off the current integration HEAD, so every merged slice is present).

## Feedback routes to the role that owns the fix
While a slice is in flight, feedback routes BACK to the RELEVANT role's session for
that slice — an architect bounce or refactorer flag about IMPLEMENTATION goes to the
slice's CODER session; a cleanup issue goes to its REFACTORER session. Continue the
role-session that already holds that work's context, never a fresh one. The dispatch
carrying feedback must restate the CURRENT worktree path and expected HEAD — an earlier
worktree may have been removed, so the session re-cd's into a freshly-added worktree
first. A DIFFERENT role, or a DIFFERENT slice, is a different session.

## Circuit-breaker (recovery only — not the default)
Reset a stuck ROLE-session (usually the coder's) to a FRESH session that re-reads the
durable state — the acceptance entrypoint, the current diff, the spec — ONLY when that
session is thrashing or its context rotted: N consecutive failures on the SAME test
with no progress, or budget burned with no diff to show. This is recovery, not how
slices normally run.
