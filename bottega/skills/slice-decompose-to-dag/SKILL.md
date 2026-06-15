---
name: slice-decompose-to-dag
description: Load ONCE at planning (coordinator + specifier) to turn an approved spec into right-sized vertical slices tagged produces/consumes/touches, derive the dependency DAG, and tag the spine. Load before any slice is dispatched.
---

# slice-decompose-to-dag — spec to a dependency DAG

Planning runs once, before any slice is dispatched. It produces the structure the
whole build is driven from: a set of right-sized vertical slices, the edges
between them, and the spine. The specifier is the coordinator's pair here; the
coordinator owns the final DAG.

## Detect the target stack first
Inspect the target root (read-only) and record the stack + the EXACT gate
commands the whole run will use, so workers never re-detect:
- A JS/TS manifest -> tests = the project's own test script (else the runner it
  configures); lint = its linter; typecheck = its type checker.
- A Python manifest -> tests = its test runner; lint = its linter; typecheck =
  its type checker.
Prefer the project's own configured scripts (package scripts, Makefile, task
runner) over hardcoded commands. COVERAGE is optional — include it only if the
project already configures it. Record stack + gate commands in the registry and
pass them into every dispatch.

## Decompose into vertical slices
A slice is ONE externally-visible behavior, end to end. Tag each slice with:
- `produces` — the contracts/interfaces/data this slice creates that others can
  build on (a function signature, an endpoint, a schema, a module boundary).
- `consumes` — the contracts it needs to already exist.
- `touches` — the files it is expected to modify.

## Right-size every slice
A slice must fit comfortably in ONE worker session: a handful of files plus its
behavior spec plus its acceptance test, implementable AND testable to green in a
single context window. If a slice won't fit, SPLIT it into more slices. Never
sub-delegate a slice to fan-out — splitting, not sub-delegating, is how the work
is bounded.

## Derive the DAG
- Edge `A -> B` exists IFF `B.consumes ∩ A.produces` is non-empty (B needs a
  contract A produces).
- Two slices are INDEPENDENT iff there is no edge either way. Independent slices
  may run in the same wave, in parallel.
- File overlap (`touches ∩ touches`) is NOT an edge. It is a MERGE COST, resolved
  at integration — never a reason to serialize two otherwise-independent slices.

## Tag the spine
Mark a slice as spine when it either:
- produces a contract consumed by TWO OR MORE slices, or
- is a schema / migration / shared interface everything else builds on.
The spine lands first and sequentially (see the wavefront skill), so dependents
can compile and author their failing tests while the real implementations
proceed in parallel.

## Ground the edges in the real repo
Do not guess contracts. Use the **investigate** skill to read the target repo so
`produces`/`consumes` reflect the actual interfaces a slice will create or call.
A DAG built on guessed edges either over-serializes (false dependencies) or
breaks at integration (missed ones).

## Hand off
- The specifier returns the behavior spec, acceptance criteria, the FAILING
  acceptance tests it can author up front, and the proposed behavior boundaries.
- The COORDINATOR owns the final ordered DAG: it accepts, splits, or re-tags the
  proposed boundaries, then writes the slices, edges, and spine tags into the
  registry. That DAG is what the human approves at the plan gate.
