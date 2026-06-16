---
name: architect-verify
description: Load ONCE at the end — the final whole-feature join by a fresh architect at the integration HEAD. Run gates, source mutation, cross-slice DRY, and APS acceptance mutation (gherkin-mutator — errors=0 with every survivor classified KILLABLE→bounce or EQUIVALENT→justified) over the assembled feature, then SIGN-OFF or BOUNCE, attributing each failure to its owning slice. Holds the bounce-loop cap.
---

# architect-verify — the final whole-feature join

Once the DAG has drained, a FRESH architect verifies the assembled feature at the
integration HEAD. It judges the whole, not slice-by-slice, and writes no feature code
— it signs off or bounces.

## Externalize the heavy lifting
Do not reason over raw whole-repo tokens. Run deterministic tools and reason over
their DISTILLED outputs: the source-mutation tool → a survivor list; the duplication
detector → a report; `gherkin-mutator` → a survived/killed summary; the gate suite →
pass/fail. Apply judgment to those results, not to a re-read of every file.

Scope: this gate is Python/pytest (the only stack APS is wired for). Each tool's
command below ACTUALLY redirects its output into the run's evidence dir
`EV="$TARGET_ROOT/.bottega/verify/<integration_head>"` (`mkdir -p "$EV"` first); the
set of files WRITTEN here is exactly the set the verdict and pr-assemble CHECK. Record
each path in the registry `verification` block.

## Sequence (each step gates the next; a failure that warrants it is a BOUNCE)
1. **Full gates** — tests / lint / typecheck (and coverage if configured), green end
   to end over the whole feature.
2. **Source mutation** — REQUIRED. `mutmut` from the pinned APS venv, output captured.
   `set -o pipefail` so a `mutmut` crash propagates instead of being masked by `tee`'s
   exit 0:
   ```sh
   set -o pipefail
   "$APS_VENV/bin/mutmut" run 2>&1 | tee "$EV/source-mutation.txt"   # checks ${PIPESTATUS[0]}
   ```
   Cover the uncovered and KILL SURVIVORS. A surviving source mutant is a BOUNCE.
3. **Cross-slice DRY** — REQUIRED. A duplication detector (jscpd), output captured (same
   `pipefail` so a `jscpd` crash is not masked by `tee`):
   ```sh
   set -o pipefail
   jscpd --pattern "**/*.py" 2>&1 | tee "$EV/dry.txt"               # checks ${PIPESTATUS[0]}
   ```
   SIGNIFICANT duplication — especially helpers several slices reinvented — is a BOUNCE.
4. **Acceptance mutation (APS)** — REQUIRED, complementary to source mutation: source
   mutation mutates the CODE, APS mutation mutates the GHERKIN acceptance to prove the
   acceptance suite actually constrains behavior. Run `gherkin-mutator` (the threaded
   `APS_MUTATOR`) over EVERY `features/*.feature` — not one hardcoded feature — with the
   venv's `aps-adapter` as the runner, capturing all output to the evidence file. Mutate
   a COPY of each feature (gherkin-mutator writes a manifest stamp INTO `--feature`, so
   running against the tracked file would dirty committed features and make reruns skip):
   ```sh
   set -o pipefail   # a gherkin-mutator CRASH must propagate, not be masked by tee
   : > "$EV/acceptance-mutation.txt"
   for feat in features/*.feature; do
     id="$(basename "$feat" .feature)"
     rm -rf "build/acc-mut/$id"; mkdir -p "build/acc-mut/$id"
     cp "$feat" "build/acc-mut/$id/feature"          # mutate the COPY, never the tracked feature
     "$APS_MUTATOR" --feature "build/acc-mut/$id/feature" --work-dir "build/acc-mut/$id/wd" \
       --generated-dir "acceptance/generated/$id" --level hard \
       --runner-worker "$APS_ADAPTER $APS_VENV/bin/pytest acceptance/generated/$id -q" \
       2>&1 | tee -a "$EV/acceptance-mutation.txt"
   done
   ```
   A fresh `--work-dir` + an un-stamped COPY guarantees an authoritative run (never a
   differentially-skipped `total=0`). The `--runner-worker` invokes
   `$APS_VENV/bin/pytest` EXPLICITLY — bare `pytest` resolves to the SYSTEM interpreter,
   which lacks `aps_kit` and errors EVERY mutant (`ModuleNotFoundError: aps_kit`); the
   explicit venv pytest makes the command self-contained, no `PATH` surgery. After the
   loop, confirm `git -C "$TARGET_ROOT" status --porcelain features/` is EMPTY — tracked
   features must be untouched. Note `gherkin-mutator` exits 1 whenever ANY mutant
   survives OR errors, so a non-zero exit is NOT itself a verdict — read the summary.

   **Classify survivors — NOT literal `survived=0`.** gherkin-mutator mutates example
   CELLS, and some mutations cannot change a scenario's outcome — equivalent mutants,
   inherently unkillable EVEN WHEN the glue correctly reads operand values from the IR
   (e.g. flipping one non-numeric operand to another in a type-only "rejects non-numeric"
   scenario; the dividend in a divide-by-zero scenario; a short-circuited second
   operand). A literal `survived=0` bar is therefore UNSATISFIABLE for any feature with
   validation or error handling. For EACH surviving mutant the architect decides:
   - **KILLABLE** — the mutated cell IS outcome-determining and the suite failed to
     catch it ⇒ a weak/vacuous example or a hardcoded handler ⇒ BOUNCE the owning slice.
   - **EQUIVALENT** — the mutated cell cannot change the scenario outcome ⇒ acceptable,
     WITH a one-line written justification.
   A survivor that mutates an OUTCOME cell — the `expected` / `result` the scenario
   ASSERTS on — is PRESUMPTIVELY KILLABLE: it may be classed EQUIVALENT only if the
   architect can prove the mutated cell cannot affect ANY observable assertion (almost
   never — an outcome-cell survivor usually means a weak/vacuous test ⇒ BOUNCE). Default
   the benefit of the doubt to KILLABLE; EQUIVALENT is the exception you must justify.
   `errors > 0` is ALWAYS a BOUNCE (harness/tool failure — e.g. a runner that can't
   import `aps_kit`). Record every survivor's `{mutation, class, justification}` into
   `$EV/equivalent-mutants.json` AND the registry `verification` block.
   (`examples/aps-equivalent-mutants` is the runnable regression for this gate;
   `examples/aps-step-isolation` covers the all-killed case.)
5. **Verdict** — SIGN-OFF requires, over the whole feature set: `errors=0`, **ZERO
   killable survivors**, every equivalent survivor justified, source-mutation survivors
   killed, DRY clean — AND all four evidence files exist (`source-mutation.txt`,
   `dry.txt`, `acceptance-mutation.txt`, `equivalent-mutants.json`). Record the paths +
   `verdict: sign-off` in the registry `verification` block. Any killable survivor, any
   `errors>0`, or a missing evidence / justification record ⇒ BOUNCE.

## Bounded targeted sub-sessions are allowed
The architect may run a small, BOUNDED number of targeted passes — one per survivor
cluster to understand why a mutant lives, or a focused fresh-eyes security / design
read of a specific boundary. Scoped checks, never a re-implementation loop.

## On a bounce (the bounce-loop cap lives here)
- Attribute each failure to the OWNING slice — use **investigate** to pin a survivor,
  a duplication cluster, or a surviving acceptance mutant to the slice that introduced
  it.
- Route each fix back to that slice's relevant role-session (continue it, per
  run-slice-pipeline's feedback rule) — a surviving source/acceptance mutant or
  behavior gap to its CODER session, a duplication cluster to its REFACTORER session —
  with a concrete recommendation and the gate / mutation / DRY evidence.
- Re-run **integrate-wave** for the touched slices, then re-verify. CAP the bounce
  loop at roughly THREE rounds (the registry's `bounce_round` field); if it still
  can't sign off, escalate to the human with specifics and END THE TURN to await their
  answer rather than looping forever.

## After sign-off
On SIGN-OFF the coordinator runs **pr-assemble** to open the ONE PR for the
integration branch; a human merges it. The architect never opens or merges a PR.
