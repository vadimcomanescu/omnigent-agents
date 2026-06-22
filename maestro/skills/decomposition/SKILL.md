---
name: decomposition
description: How maestro cuts a goal into buildable units across two axes: the delivery axis (each unit is one PR, cut by independent shippable value) and the execution axis (fresh implementer sessions sized to one clean context, looped on one branch). Binds a PROOF section into every unit's acceptance contract, then routes units to fanout and cross-review. Use when breaking a goal, feature, bug, PRD, or review finding into units, deciding what becomes one PR versus several, sizing a unit against the context window, or writing an acceptance contract before dispatch.
---

# decomposition: provable, context-sized units

Two orthogonal axes, never collapsed. Value cuts the PRs. Context-fit sizes the
execution. Proof gates them, and every proof clause must be able to fail.

## Procedure

1. **Map dependencies and shippable value.** List the real contracts,
   migrations, prompt surfaces, UI states, and gates that constrain order. A
   unit is the smallest change that ships observable value on `main` by itself.
   Do not invent an edge for mere proximity; place a contract-defining unit
   (schema, interface, prompt contract) before its consumers. Name units in the
   domain ("settle invoice retry policy", not "update worker code") so the list
   reads as a product story and bad splits expose themselves.

2. **Cut the DELIVERY axis into PRs by shippable value.** Split into separate
   PRs only when the work divides AND each half independently ships value on
   `main`. Proof-divisibility only removes an objection to splitting; it never
   supplies a reason. A single indivisible proof obligation may NOT be split
   into two PRs (if it is merely too big, that is the execution axis, step 4).
   - Localizability of proof is a SMELL, not the cut. Proof will not localize
     (inherently cross-subsystem), merge into one vertical slice and never
     split by layer. Proof divides but a half is valueless alone (a helper with
     no caller), fold it into its consumer's PR and never ship it solo.

3. **Write each unit's acceptance contract with a PROOF section.** maestro
   authors the obligation; the implementer authors the artifacts.
   - **Gate commands**, stamped from the repo's standing gate manifest
     (test / typecheck / lint) and parameterized by unit type, never
     hand-written per unit. If the commands are unknown, the first session
     discovers and records them before implementing.
   - **Behavioral acceptance** as observable outcomes at the unit boundary
     (inputs to results, error cases; for a fix, the repro signature that must
     now hold). Never test names, fixtures, mocks, counts, or a TDD mandate.
   - **Risk-proportional proof.** New behavior gets a test that exercises it; a
     bug fix gets a regression test red-before / green-after; a refactor or
     infra change keeps the standing suite green and matches its contracted
     diff shape. "No proof, not a unit" means evidence proportional to risk,
     not "always add tests".
   - **Tightness band.** Every behavioral clause must survive any
     behavior-preserving refactor (else it is too tight, push it down to the
     implementer) AND fail on at least one realizable behavior-breaking change
     (else it is too loose; a clause that cannot fail is not proof).

4. **Estimate context-fit per unit** (deterministic, no model call): files
   touched, subsystems, simultaneous invariants, expected diff size, gate
   localizability. Route:
   - Fits one clean context, one fresh implementer session.
   - One shippable unit, too big for one context, a LOOP of fresh sessions on
     one branch/worktree, same PR. Continuity lives on disk: the plan file
     holds the contract, which acceptance outcomes are green and which remain
     (the proof frontier), and a decisions / rejected-approaches log. Each
     fresh session re-runs the gates, reads green first, then works the open
     items.
   - Secretly several shippable units, back to step 2 for more PRs.

5. **Route to the sibling skills.** Independent units in parallel go to
   `fanout` (one worktree + implementer + PR each). Every finished PR goes to
   `cross-review`: maestro runs the deterministic gates green ITSELF first
   (green means maestro observed it, not the implementer's self-report), then a
   DIFFERENT-vendor reviewer gets the diff + contract only and is the backstop
   on proof quality, not the first line.

6. **maestro never merges.** The PR is the deliverable; the human merges.

## Notes

- maestro writes ACCEPTANCE (observable outcomes + gate commands); the
  implementer writes ASSERTIONS (tests, fixtures, mocks). Stop at test-design
  altitude. Pinning internal structure under the name of verification defeats
  the cross-vendor check.
- Stay test-strategy-agnostic. Test-first versus test-after is the
  implementer's choice (the `tdd` skill is opt-in) and is unverifiable from a
  diff + contract anyway. This flips only for a regulated domain that needs TDD
  as an audit artifact.
- Separate the deterministic gate subset (machine-run, binary, the hard
  pre-review precondition) from behavioral evidence (judgment or manual,
  captured as a committed artifact so it travels in the diff + contract and is
  judged by the reviewer). Only the deterministic subset gates cross-review.
- A unit is not DISPATCHABLE until its PROOF section exists, and not DONE until
  maestro has observed its gates green.
- If a fresh session finds a unit unverifiable alone, escalate to
  re-decomposition; do not silently edit the acceptance meaning. The
  implementer never self-certifies its own bar; maestro applies the tightness
  band to any implementer-proposed clause.
- Never split a PR to relieve context pressure. Shippable value splits the
  delivery axis; context-fit loops the execution axis. They are different
  levers.
