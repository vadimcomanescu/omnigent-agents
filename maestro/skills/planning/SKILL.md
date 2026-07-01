---
name: planning
description: Turn a goal, spec, PRD, issue, or bug into a decomposed, dependency-ordered plan whose units each map to ONE worktree, ONE implementer, ONE PR, ONE cross-vendor review. Use before fanout when work is non-trivial, spans multiple files/units, or needs a human plan gate. The plan is the deliverable; maestro never implements, reviews, or merges from this skill.
---

# planning — decompose a goal into reviewable units

## The framing axiom (everything derives from this)

> **A planning unit is the atomic deliverable: one git worktree → one
> implementer sub-agent → one pull request → one cross-vendor review → one
> human merge.**

The unit boundary is therefore "one reviewable, independently-landable PR." If
a unit cannot reasonably become one PR, it is too broad or too entangled —
split it or reframe it. Every unit carries a **self-sufficient acceptance
contract** that a different-vendor reviewer can judge **against the diff
alone**, with no access to the worktree and no need to read the rest of the
plan. That single constraint forces every other choice here: PR-sized
granularity, decisions-not-code, enumerated test scenarios, repo-relative
paths, and non-overlapping file sets per parallel wave.

maestro is a tech lead, not a coder. This skill produces the plan and **stops
at the human plan gate**. It never writes or runs code to investigate, never
implements, never reviews, never merges. Execution is `fanout`'s job;
verification is `cross-review`'s job; merge is the human's.

## When to use

- The goal spans more than one file, unit, or concern, or is non-trivial.
- Work will fan out to parallel implementers and needs an explicit dependency
  order and non-overlapping file ownership.
- A human should approve scope and decomposition before any code is written.

## When NOT to use

- A single, obvious, one-PR change → skip planning, go straight to `fanout`
  (or a single implement dispatch).
- A read-only question ("how does X work?", "why is this failing?") → use
  `investigate`, not this.
- Pure docs/text edits maestro makes directly → no plan needed.

## Procedure

### Phase 0 — Strategy / framing gate (challenge before you decompose)

Before breaking anything down, interrogate the request itself. Keep a **low
bar to change direction** and a **high bar to stop and ask** — prefer
re-framing over halting. Ask:

- Is this the **right problem**, or a symptom of a deeper one?
- Is there a **simpler path** that makes most of the work unnecessary?
- Is it **overbuilt** — gold-plating beyond what the goal needs?
- Is it secretly **several independent projects** that each deserve their own
  plan?
- Does it rest on an **unvalidated assumption** that a cheap read-only spike
  should test first?

Do not preserve an earlier decision just because it came first. If the framing
is wrong, fix the framing before decomposing.

### Phase 1 — Read-only investigation (delegate; never read code yourself)

maestro does not inspect the codebase to plan. A quick look at a file or two
to orient is fine; real investigation is delegated. Dispatch `explore` /
`search` sub-agents (see the `investigate` skill) to map: existing patterns to
follow, the dependency graph, the **likely files each unit will touch**,
test/verification commands the repo already uses, and the top risks. Synthesize
the plan from their **structured reports**, not from your own deep code
reading. This overrides the source planners' assumption that the planner reads
the code directly — here, the planner delegates.

### Phase 2 — Decompose into units (PR-sized, vertical, non-overlapping)

- Cut the goal into **units that are each one reviewable PR**. Prefer
  **vertical slices** (a thin end-to-end capability) over horizontal layers
  when it keeps a unit independently landable.
- Give every unit a **stable U-ID** (`U1`, `U2`, …) used everywhere it is
  referenced — dependencies, waves, registry, and any follow-up edit.
- Build the dependency graph **bottom-up**: foundational units (schema, types,
  shared interfaces) before the units that consume them.
- **Files are owned, not shared, within a wave.** Two units that must edit the
  same file cannot run in the same parallel wave — either order them across
  waves or merge them into one unit. Record each unit's file set so `fanout`
  can guarantee non-overlap.

### Phase 3 — Write the acceptance contract per unit

The contract is the reviewer's yardstick, not a vague task description. Each
unit's contract MUST be judgeable from the diff alone and MUST state:

- **Goal** — the one capability this unit delivers.
- **Done-when** — concrete, observable acceptance criteria.
- **Test scenarios** — the specific cases the change must cover (happy path +
  the edges that matter). Never weaken or delete a test to make a unit pass;
  the completion standard is real green, not green-by-deletion.
- **Verification gate** — the exact deterministic commands (test / lint /
  typecheck) that must pass, named explicitly.
- **Files** — repo-relative paths the unit is expected to touch.
- **Out of scope** — what this unit deliberately does NOT do (anti-expansion).

### Phase 4 — Order into waves

Group units into execution **waves**: every unit in a wave has all its
dependencies satisfied by earlier waves and shares no files with its
wave-mates. Wave N is the `fanout` batch. State the critical path so the human
sees the longest chain.

**The wave gate is merge, not review.** `fanout` branches every worktree fresh
from the current base, and maestro never merges — the human does. So a wave's
code only becomes a usable base for the units that depend on it once the human
has **merged** that wave's PRs. Therefore dispatch a unit only after every
wave it depends on has been cross-reviewed **and merged/adopted into the
base** — not merely cross-reviewed. Dispatching a dependent wave off review
alone leaves its implementers branching without the prerequisite code, so they
fail to build against missing interfaces or duplicate the earlier PR.

**Two kinds of edge force a unit to wait for another unit's merge:** a
**dependency edge** (it needs the other's code) and a **shared-file edge**
(both touch the same file, so the later unit must branch from a base that
already contains the earlier one's edits, or `fanout` produces conflicting PRs
from the same base). Treat a shared-file conflict as an explicit barrier,
exactly like a dependency — record it in the unit's deps so `fanout` never
dispatches the two concurrently. Only units with **neither** edge to any
un-merged unit may run concurrently; it is these edges, not the wave number,
that force the wait.

### Phase 5 — Right-size and confidence-check

Match the artifact to the work: a 2-unit plan is a short list, a 12-unit plan
needs the full graph. Do a deepening pass on the **riskiest** units only —
separate **planning-time unknowns** (must resolve now, via another `explore`
spike) from **implementation-time unknowns** (safe to leave to the
implementer, but name them). Defer scope creep into an explicit "Later / out of
scope" section rather than smuggling it into a unit.

### Phase 6 — Human plan gate

Write the plan to `.maestro/registry.json` (units, U-IDs, contracts, file sets,
waves, deps) and present it to the human. **Stop here.** Do not dispatch
implementers until the human approves scope and decomposition. On approval,
hand off to `fanout` (one worktree + implementer + PR per unit) then
`cross-review` (different-vendor verification); the human merges.

## Unit template

```
### U<id> — <short title>
Goal:        <one capability, one PR>
Depends on:  <U-ids, or "none">
Files:       <repo-relative paths this unit owns>
Approach:    <decisions + patterns to follow — NOT code>
Done-when:   <observable acceptance criteria>
Test:        <scenarios to cover; existing tests must stay green, not weakened>
Verify:      <exact test/lint/typecheck commands>
Out of scope:<what this unit will not do>
Open Qs:     <implementation-time unknowns left to the implementer>
```

## Sizing tiers (rough, for granularity not estimation)

- **XS** — one file, a few lines; trivial.
- **S** — one file or one tight cluster; one clear behavior.
- **M** — a few files, one capability; the typical unit. **This is the target.**
- **L** — many files or cross-cutting; **split it** unless truly atomic.
- **XL** — its own mini-project; **always split** into a multi-unit sub-plan.

## Discipline rules

- **Decisions, not code.** Capture framing, scope boundaries, decisions +
  rationale, unit boundaries, files, patterns, test scenarios, and risks.
  Directional pseudo-code or a diagram is allowed ONLY when prose cannot carry
  the architecture; full implementation code and micro-step choreography are
  not.
- **Zero-context readers.** Each unit must be executable by a fresh-context
  implementer who cannot see your reasoning or the other units. Repo-relative
  paths, named commands, no "as discussed."
- **One plan per subsystem.** If the goal spans unrelated subsystems, produce
  separate plans rather than one sprawling document.
- **Never weaken tests to pass.** A unit is done when its real tests are green,
  never by deleting, skipping, or loosening them.
- **maestro stops at the gate.** No implement / review / merge from this skill.

## Anti-patterns

- A unit too big to review as one PR, or that touches a file another wave-mate
  also edits.
- A contract a different-vendor reviewer could not judge from the diff alone.
- Planning by reading the code yourself instead of delegating to `explore`.
- Smuggling scope creep into a unit instead of deferring it to "Later".
- Embedding full implementation code in the plan.
- Dispatching implementers before the human approves the plan gate.

## Done checklist

- [ ] Framing challenged (Phase 0); right problem, right size.
- [ ] Investigation delegated; plan grounded in sub-agent reports.
- [ ] Every unit is one PR with a stable U-ID and an owned, non-overlapping
      file set.
- [ ] Every unit has a diff-judgeable acceptance contract (done-when, test
      scenarios, verify commands, out-of-scope).
- [ ] Units ordered into dependency-correct waves; critical path stated.
- [ ] Riskiest units deepened; planning-time unknowns resolved.
- [ ] Plan written to `.maestro/registry.json` and presented at the human gate
      — no implementers dispatched yet.
