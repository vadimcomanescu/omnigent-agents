---
name: architect-verify
description: Load ONCE at the end — the final whole-feature join by a fresh architect at the integration HEAD. Run gates, mutation, and cross-slice DRY over the assembled feature and SIGN-OFF or BOUNCE, attributing each failure to its owning slice.
---

# architect-verify — the final whole-feature join

Once the DAG has drained, a FRESH architect verifies the assembled feature at the
integration HEAD. It judges the whole, not slice-by-slice, and it writes no
feature code — it signs off or bounces.

## Externalize the heavy lifting
Do not reason over raw whole-repo tokens. Run deterministic tools and reason over
their DISTILLED outputs:
- the mutation tool -> a survivor list,
- the duplication detector -> a duplication report,
- the gate suite -> pass / fail.
The architect's judgment is applied to these distilled results, not to a re-read
of every file.

## Sequence (each step gates the next)
1. **Full gates** — tests / lint / typecheck (and coverage if configured), green
   end to end over the whole feature.
2. **Mutation** — run the stack's mutation tool over the assembled feature and
   work the survivor list. A SURVIVING mutant is a BOUNCE.
3. **Cross-slice DRY** — run the duplication detector across the whole feature.
   SIGNIFICANT duplication (especially helpers that several slices reinvented) is
   a BOUNCE.
4. **Verdict** — SIGN-OFF (ship-ready) or BOUNCE.

## Bounded targeted sub-sessions are allowed
The architect may run a small, BOUNDED number of targeted passes — one per
survivor cluster to understand why a mutant lives, or a focused fresh-eyes
security / design read of a specific boundary. These are scoped checks, not a
re-implementation loop: the architect never micro-loops the slices' code.

## On a bounce
- Attribute each failure to the OWNING slice — use the **investigate** skill to
  pin a survivor or a duplication cluster to the slice that introduced it.
- Route each fix back to that slice's OWN session (continue it, per
  run-slice-pipeline's feedback rule) with a concrete recommendation and the gate
  / mutation / DRY evidence.
- Re-run **integrate-wave** for the touched slices, then re-verify. Cap the
  bounce loop at roughly THREE rounds; if it still can't sign off, escalate to the
  human with specifics rather than looping forever.

## After sign-off
On SIGN-OFF the coordinator opens the ONE PR for the integration branch; the
human merges it. The architect never opens or merges a PR.
