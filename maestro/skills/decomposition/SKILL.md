---
name: decomposition
description: How maestro cuts a goal into buildable units across two axes (the delivery axis, where each unit is one PR cut by independent shippable value, and the execution axis, where fresh implementer sessions are sized to one clean context and looped on one branch), then ORDERS those units with an explicit dependency graph and a topological sort (Kahn) whose leftover cycles are a wrong-cut alarm and whose layers are the parallel fanout waves. Binds a PROOF section into every unit's acceptance contract, checks each contract for internal contradiction before dispatch, then routes units to fanout and cross-review. Use when breaking a goal, feature, bug, PRD, or review finding into units, deciding what becomes one PR versus several, ordering units that depend on each other, sizing a unit against the context window, or writing an acceptance contract before dispatch.
---

# decomposition: provable, context-sized, dependency-ordered units

Decomposition is two separate problems, and conflating them is the classic
mistake. WHERE the boundaries go is judgment: no algorithm tells you "settle
invoice retry policy" is one unit. WHAT ORDER you build and merge the units in,
given those boundaries, is NOT judgment: it is a dependency graph plus a
topological sort, and that part is mechanical. Do the judgment first, then run
the algorithm on its output, and never dress one up as the other. On top sit
two orthogonal sizing axes: value cuts the PRs, context-fit sizes the
execution, proof gates them, and every proof clause must be able to fail.

## Procedure

1. **Cut units by judgment, named in the domain.** List candidate units as the
   smallest changes that each ship observable value on `main` by themselves.
   Name them in the domain ("settle invoice retry policy", not "update worker
   code") so the list reads as a product story and a bad split exposes itself.
   This step is heuristic and stays heuristic; do not pretend an algorithm
   places the boundaries.

2. **Build the dependency graph, then topologically order it with Kahn's
   algorithm.** This is the mechanical step, and it is where ordering rigor
   lives. The earlier version of this skill ordered units "by hand"; that was
   the one place real rigor was missing.
   - **Nodes** are the units from step 1. A directed **edge A -> B** exists
     when B cannot be built or proven until A exists: B consumes A's schema,
     interface, prompt contract, migration, or output type. The test for an
     edge is "does B's contract reference something only A defines?", never
     mere file proximity or topical similarity.
   - **Run Kahn.** Compute every node's in-degree (count of incoming edges).
     The set of nodes with in-degree 0 is the current wave; emit it, remove
     those nodes, and decrement each successor's in-degree; the successors that
     drop to 0 form the next wave. Repeat until the graph is empty. The wave
     order is the build-and-merge order, so a contract-defining unit (schema,
     interface, prompt contract) always lands in an earlier wave than its
     consumers, by construction rather than by hope.
   - **A leftover cycle is a HARD wrong-cut alarm, not something to order
     around.** If the drain stalls with nodes still holding in-degree > 0,
     those nodes form a cycle: two "independent" units actually depend on each
     other, so the cut is wrong. Do not linearize it by guessing an order.
     Re-cut: either merge the cyclic nodes into one vertical-slice unit, or
     extract the shared contract they both need into a new upstream unit that
     breaks the cycle, then rebuild the graph. A cycle caught here is a bug the
     decomposition would otherwise have shipped.
   - **Each Kahn wave is a parallel-safe batch.** Nodes within one wave have no
     edges between them, so they are exactly the set `fanout` may run in
     parallel. Successive waves are sequential: do not start wave N+1 until
     wave N's units are merged, because wave N+1's contracts assume them.

3. **Cut the DELIVERY axis into PRs by shippable value.** Split into separate
   PRs only when the work divides AND each half independently ships value on
   `main`. Proof-divisibility only removes an objection to splitting; it never
   supplies a reason. A single indivisible proof obligation may NOT be split
   into two PRs (if it is merely too big, that is the execution axis, step 5).
   - Localizability of proof is a SMELL, not the cut. If proof will not
     localize (inherently cross-subsystem), merge into one vertical slice and
     never split by layer. If proof divides but a half is valueless alone (a
     helper with no caller), fold it into its consumer's PR and never ship it
     solo.

4. **Write each unit's acceptance contract with a PROOF section, then prove the
   contract is self-consistent before dispatch.** maestro authors the
   obligation; the implementer authors the artifacts.
   - **Gate commands**, stamped from the repo's standing gate manifest
     (test / typecheck / lint) and parameterized by unit type, never
     hand-written per unit. If the commands are unknown, the first session
     discovers and records them before implementing.
   - **Behavioral acceptance** as observable outcomes at the unit boundary
     (inputs to results, error cases; for a fix, the repro signature that must
     now hold). Never test names, fixtures, mocks, counts, or a TDD mandate.
   - **Worked examples.** Pin at least one concrete `input -> exact output` per
     behavioral clause, including every named trap case. These are the
     contract's ground truth, not decoration; reviewers and adjudicators reason
     from them.
   - **Contract-consistency gate (load-bearing).** Before a unit is
     dispatchable, verify that no two clauses or worked examples demand a
     different output for the same input, and that every prose clause agrees
     with every worked example it touches. A contract that contradicts itself
     CANNOT be satisfied by any implementation: the agent is forced to guess a
     product decision and will regress some other case while papering over the
     conflict with a branch. A detected self-contradiction is a
     re-decomposition trigger and a question for the human, never something the
     implementer resolves silently.
   - **Risk-proportional proof.** New behavior gets a test that exercises it; a
     bug fix gets a regression test red-before / green-after; a refactor or
     infra change keeps the standing suite green and matches its contracted
     diff shape. "No proof, not a unit" means evidence proportional to risk,
     not "always add tests".
   - **Tightness band.** Every behavioral clause must survive any
     behavior-preserving refactor (else it is too tight, push it down to the
     implementer) AND fail on at least one realizable behavior-breaking change
     (else it is too loose; a clause that cannot fail is not proof).

5. **Estimate context-fit per unit** (deterministic, no model call): files
   touched, subsystems, simultaneous invariants, expected diff size, gate
   localizability. Route:
   - Fits one clean context: one fresh implementer session.
   - One shippable unit, too big for one context: a LOOP of fresh sessions on
     one branch/worktree, same PR. Continuity lives on disk: the plan file
     holds the contract, which acceptance outcomes are green and which remain
     (the proof frontier), and a decisions / rejected-approaches log. Each
     fresh session re-runs the gates, reads green first, then works the open
     items.
   - Secretly several shippable units: back to step 1 for more units, then
     re-run the graph in step 2.

6. **Route to the sibling skills, wave by wave.** Within a Kahn wave, the
   independent units go to `fanout` in parallel (one worktree + implementer +
   PR each). Every finished PR goes to `cross-review`: maestro runs the
   deterministic gates green ITSELF first (green means maestro observed it, not
   the implementer's self-report), then a DIFFERENT-vendor reviewer gets the
   diff + contract only and judges the diff against the CONTRACT TEXT and its
   worked examples, free to construct its own adversarial inputs. A test suite
   is a set of sampled points and is fallible in both directions: it passes
   wrong code (missing or thin cases) and fails right code (a wrong expected
   value). So the contract review is the enforcing gate, not the tests, and it
   is mandatory on every unit, never sampled. A gate you may skip is not a
   gate.

7. **maestro never merges.** The PR is the deliverable; the human merges, in
   Kahn-wave order.

## Notes

- maestro writes ACCEPTANCE (observable outcomes, worked examples, gate
  commands); the implementer writes ASSERTIONS (tests, fixtures, mocks). Stop
  at test-design altitude. Pinning internal structure under the name of
  verification defeats the cross-vendor check.
- The contract review can and will fail a unit whose suite is green, and an
  implementer can correctly refuse a contract test that is itself wrong. Both
  are the gate working, not failing. Route a disputed test to an independent
  adjudicator that reads only the contract and its worked examples, never to
  the implementer's own say-so and never to the test author who wrote it.
- Stay test-strategy-agnostic. Test-first versus test-after is the
  implementer's choice (the `tdd` skill is opt-in) and is unverifiable from a
  diff + contract anyway. This flips only for a regulated domain that needs TDD
  as an audit artifact.
- Separate the deterministic gate subset (machine-run, binary, the hard
  pre-review precondition) from behavioral evidence (judgment or manual,
  captured as a committed artifact so it travels in the diff + contract and is
  judged by the reviewer). Only the deterministic subset gates cross-review.
- A unit is not DISPATCHABLE until its PROOF section exists and its contract
  passes the consistency gate, and not DONE until maestro has observed its
  gates green AND a different-vendor review against the contract comes back
  clean.
- If a fresh session finds a unit unverifiable alone, or finds its contract
  self-contradictory, escalate to re-decomposition; do not silently edit the
  acceptance meaning. The implementer never self-certifies its own bar.
- Never split a PR to relieve context pressure. Shippable value splits the
  delivery axis; context-fit loops the execution axis; the dependency graph
  orders the waves. Three different levers, kept separate.
