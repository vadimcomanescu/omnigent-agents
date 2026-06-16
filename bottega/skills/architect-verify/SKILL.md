---
name: architect-verify
description: Load ONCE at the end — the final whole-feature join by a fresh architect at the integration HEAD. Run gates, source mutation, cross-slice DRY, and APS acceptance mutation (gherkin-mutator, survived=0/errors=0) over the assembled feature, then SIGN-OFF or BOUNCE, attributing each failure to its owning slice. Holds the bounce-loop cap.
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

## Sequence (each step gates the next; a failure that warrants it is a BOUNCE)
1. **Full gates** — tests / lint / typecheck (and coverage if configured), green end
   to end over the whole feature.
2. **Source mutation** — REQUIRED. The stack's tool: Python → `mutmut` from the pinned
   APS venv (`"$APS_VENV/bin/mutmut"`); TypeScript → Stryker. Cover the uncovered and
   KILL SURVIVORS. A surviving source mutant is a BOUNCE.
3. **Cross-slice DRY** — REQUIRED. The stack's duplication detector (jscpd or
   equivalent) across the whole feature. SIGNIFICANT duplication — especially helpers
   several slices reinvented — is a BOUNCE.
4. **Acceptance mutation (APS)** — REQUIRED, complementary to source mutation: source
   mutation mutates the CODE, APS mutation mutates the GHERKIN acceptance to prove the
   acceptance suite actually constrains behavior. Run `gherkin-mutator` (the threaded
   `APS_MUTATOR`) per feature, with the pinned venv's `aps-adapter` as the runner:
   ```sh
   "$APS_MUTATOR" \
     --feature features/<id>.feature \
     --work-dir build/acceptance-mutation \
     --generated-dir acceptance/generated/<id> \
     --level hard \
     --runner-worker "$APS_ADAPTER pytest acceptance/generated/<id> -q"
   ```
   PASS is exit 0 with a `survived=0 errors=0` summary; any survived or errored mutant
   (exit 1) is a BOUNCE. This is the mechanism the architect now uses for acceptance
   mutation — it is NOT a "no APS / no Gherkin" exclusion; APS acceptance mutation and
   source mutation are both mandatory and complementary.
   - **Use a FRESH `--work-dir`.** `gherkin-mutator` caches results per `--work-dir`: a
     re-run against a populated one reports `skipped_scenarios`/`skipped_mutations`
     with `total=0` and proves nothing. `rm -rf` the work-dir first; the authoritative
     result is the run that reports `total=N killed=N` (with `survived=0 errors=0`),
     never a skipped re-run.
5. **Verdict** — SIGN-OFF (ship-ready) or BOUNCE.

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
