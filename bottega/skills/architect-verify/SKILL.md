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
   set -o pipefail   # a gherkin-mutator non-zero exit must propagate, not be masked by tee
   : > "$EV/acceptance-mutation.txt"
   for feat in features/*.feature; do
     id="$(basename "$feat" .feature)"
     rm -rf "build/acc-mut/$id"; mkdir -p "build/acc-mut/$id"
     cp "$feat" "build/acc-mut/$id/feature"          # mutate the COPY, never the tracked feature
     "$APS_MUTATOR" --feature "build/acc-mut/$id/feature" --work-dir "build/acc-mut/$id/wd" \
       --generated-dir "acceptance/generated/$id" --level hard \
       --runner-worker "$APS_ADAPTER pytest acceptance/generated/$id -q" \
       2>&1 | tee -a "$EV/acceptance-mutation.txt"
     [ "${PIPESTATUS[0]}" -eq 0 ] || { echo "BOUNCE: gherkin-mutator failed on $id"; break; }
   done
   ```
   PASS is exit 0 with a `total=N killed=N survived=0 errors=0` summary per feature; any
   survived or errored mutant (exit 1) is a BOUNCE. A fresh `--work-dir` + an un-stamped
   COPY guarantees an authoritative run (never a differentially-skipped `total=0`). This
   is the mechanism the architect uses — NOT a "no APS / no Gherkin" exclusion; APS
   acceptance mutation and source mutation are both mandatory and complementary. After
   the loop, confirm `git -C "$TARGET_ROOT" status --porcelain features/` is EMPTY — the
   tracked features must be untouched.
5. **Verdict** — SIGN-OFF only when all three evidence files (`source-mutation.txt`,
   `dry.txt`, `acceptance-mutation.txt`) exist and show green (gates pass, source
   survivors killed, DRY clean, acceptance `survived=0 errors=0`); record the three
   paths + `verdict: sign-off` in the registry `verification` block. Otherwise BOUNCE.

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
