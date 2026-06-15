# bottega — a software development team for omnigent

**bottega** is a self-contained omnigent team that builds a feature in a target
software project. A **coordinator** (team lead) leads four specialist roles —
specifier, coder, refactorer, and architect — each with one fixed
responsibility. The coordinator decomposes a **decent PRD** into a **dependency
DAG of small vertical slices**, lands the shared **spine** first, then drives the
independent slices in **parallel waves**, assembling each wave onto one
**integration branch** and finishing with a whole-feature architect verification.

The coordinator writes no code and never merges. The input is a **decent PRD**;
from there bottega runs **fully automatically** — dividing the PRD into executable
spec criteria, then spine-first wavefront → integrate → verify — with **no
mid-process human gate**, and opens **one PR** at the end for a human to merge (it
never merges; there is no auto-merge). The verbose procedures live in **on-demand
skills**; the coordinator holds only the DAG, the width policy, and the registry,
and loads the right skill at each stage.

## The model: slices, a DAG, and parallel waves

A single worker driving an entire feature accumulates context until it overflows.
bottega bounds each worker to one slice and parallelizes across the slices that do
not depend on each other:

- **Vertical slices.** The spec is split into small **vertical slices** — one
  acceptance behavior each — sized so a fresh worker can implement *and* test it to
  green in a single context window. If a slice is too big, it is **split** before
  dispatch; it is never sub-delegated. "Fits one session" is the invariant.
- **A dependency DAG.** Each slice is tagged `produces` / `consumes` / `touches`.
  An edge `A → B` exists iff `B.consumes ∩ A.produces` is non-empty. Two slices are
  **independent** iff there is no edge either way. File overlap (`touches`) is *not*
  an edge — it is a merge cost resolved at integration, never a reason to serialize.
- **Spine first.** A slice is **spine** when it produces a contract consumed by two
  or more slices, or is a schema / migration / shared interface. The spine lands
  first and sequentially — often as a thin **contract** slice (just the
  interface / signature / stub / migration) so dependents can compile and author
  failing tests against a real contract while their implementations proceed later.
- **Whole slice per session.** The coder owns the **entire slice in one persistent
  session**: red → green → refactor is an **inner loop inside that session**, not a
  fresh session per micro-step, and the slice is never carved into sub-tasks farmed
  to other sessions. Review feedback on a slice routes **back to that slice's own
  session**, never a fresh one.
- **Parallel only across independent slices.** A fresh session per *new* slice;
  parallelism only across slices with no edge either way. A degenerate DAG — a pure
  chain where each slice consumes the previous — collapses to one slice per wave,
  i.e. the sequential loop. Width is an upper bound (default conservative, cap ~5),
  not a target.

## On-demand skills

The methodology is factored into skills the coordinator loads when needed
(auto-discovered from `skills/<name>/SKILL.md`):

| Skill | When it loads | What it does |
|-------|---------------|--------------|
| **slice-decompose-to-dag** | once at planning | spec → right-sized slices tagged `produces`/`consumes`/`touches`; derives the edges and tags the spine |
| **run-slice-pipeline** | per slice, in the worker session | specifier → coder (TDD inner loop) → refactorer for ONE slice in ONE worktree |
| **slice-wavefront** | once, the orchestration loop | integration branch, spine-first, then dependency-ordered parallel waves; durable + resumable |
| **integrate-wave** | after each wave | detect cross-slice duplication, merge each slice branch one at a time, re-green the gates |
| **architect-verify** | once, at the end | gates → mutation → cross-slice DRY over the whole feature; SIGN-OFF or BOUNCE |
| **investigate** | at DAG construction and on a bounce | delegated read-only recon to ground real contract edges and attribute failures to slices |

## Pipeline

```
                 feature request
                       │
            ┌──────────▼───────────┐
            │     coordinator      │  detects stack, decomposes the spec into a
            │  writes no code,     │  dependency DAG of slices, owns the registry
            │  never merges        │  + the one integration branch
            └──────────┬───────────┘
                       │ slice-decompose-to-dag (+ specifier, + investigate)
            ┌──────────▼───────────┐
            │      specifier       │  behavior spec, acceptance criteria, FAILING
            │                      │  acceptance tests, proposed boundaries
            └──────────┬───────────┘
                       │ slice-wavefront — automatic, no human gate
   ┌───────────────────▼─────────────────────────────────────┐
   │  spine first (sequential): land the shared contracts     │
   │  ──────────────────────────────────────────────────────  │
   │  wave loop until the DAG drains:                          │
   │    ready set = independent slices whose producers merged  │
   │    spin K worktrees off the current integration HEAD      │
   │    K parallel run-slice-pipeline (own worktree each):     │
   │        specifier → coder (red→green→refactor inner loop)  │
   │                  → refactorer                             │
   │    integrate-wave: detect dup, merge each slice/* one at  │
   │        a time, re-green gates, advance integration HEAD   │
   └───────────────────┬─────────────────────────────────────┘
                       │ DAG drained → architect-verify
            ┌──────────▼───────────┐
            │      architect       │  gates → mutation → cross-slice DRY over the
            │                      │  whole feature; SIGN-OFF or BOUNCE
            └──────────┬───────────┘
                       │ on sign-off → coordinator opens the ONE PR
         ╔═════════════▼═══════════════╗
         ║   open ONE PR → human merges ║   coordinator opens one PR and STOPS;
         ╚═════════════════════════════╝   a human merges — it NEVER merges (no auto-merge)
```

Each slice runs in its **own git worktree**. Only the **coder** writes feature
code, and the roles that clean and verify it — refactorer and architect — are
**different agents**, so the implementation is always reviewed by a different
agent than wrote it. (The roster table below shows the concrete vendor split that
makes that review cross-vendor.) On a bounce, the architect attributes each
failure to the owning slice and the coordinator routes the fix back to that
slice's own session — bounded targeted passes only, never a re-implementation loop.

## Who reports to whom

The coordinator is the **hub**; every role is a spoke. There is **no peer-to-peer
handoff** — no worker ever hands off to another worker. Every role reports back
*only* to the coordinator, and every dispatch originates from the coordinator.

```
                       ┌───────────────────────────┐
        specifier ◀───▶│        coordinator        │   the HUB — owns the DAG,
        (pairs at      │   decompose · dispatch ·  │   registry, gates, the
         the front)    │   gate · record · route   │   integration branch, the one PR
                       └────┬──────────┬───────────┘
            dispatch (fresh │          │ dispatch (fresh session per slice;
             session) ──────┤          ├────── feedback CONTINUES that slice's
                            ▼          ▼              own coder/refactorer session)
                         coder     refactorer                 architect
                            │          │                          │
                            └──────────┴──────────────────────────┘
                  report back ONLY to the coordinator, never to each other:
                  HEAD + CHANGED-FILES (git diff --stat), gate output,
                  and the architect's SIGN-OFF / BOUNCE verdict
```

**One line:** the **coordinator** decomposes into a DAG, dispatches, gates,
records, and routes — and is the only node anyone reports to; the **specifier**
writes the spec + failing acceptance tests (pairs with the coordinator up front);
the **coder** TDD-implements one whole slice; the **refactorer** cleans that slice
and drives the gates green; the **architect** runs the final whole-feature
verification (gates → mutation → DRY) and returns SIGN-OFF or BOUNCE — and on a
bounce the coordinator (not the architect) routes the fix back to that slice's own
session.

## Roles

| Role | dir | harness / vendor | Owns | Does Not Own |
|------|-----|------------------|------|--------------|
| **specifier** | `agents/specifier` | claude-native | externally-visible behavior spec, acceptance criteria, the **failing acceptance tests**, and **proposed behavior boundaries** | implementation, refactors, design rulings, the DAG (the coordinator owns it) |
| **coder** | `agents/coder` | codex-native | TDD implementation of **ONE** whole slice in one persistent session until its acceptance + unit tests pass | spec authorship, structural redesign, quality gates as polish, more than one slice |
| **refactorer** | `agents/refactorer` | claude-native | structure-preserving cleanup of the just-coded slice; makes test / lint / typecheck gates green; coverage / property tests | adding or altering behavior, redesigning module boundaries, other slices |
| **architect** | `agents/architect` | claude-native | high-level design, module boundaries, dependency direction, **final verification** over the assembled feature (full gates → **mutation testing, killing survivors** → **cross-slice DRY**) + sign-off/bounce | writing feature code, rewriting slices, running integration, merging |

The coder runs on a different vendor than the refactorer and architect, which is
what makes the always-different-agent review **cross-vendor**. Each role prompt
carries explicit `## Owns` / `## Does Not Own` sections, an instruction to work
**only the single slice handed in**, and a hand-back contract (new HEAD commit, a
**CHANGED-FILES list** — `git diff --stat` — what it did, concerns, ready-for-next).

## Durable + restorable registry

The coordinator's working memory is **durable and restorable** — it writes no
code, so build state cannot live in its context alone.

- **Persisted.** The registry lives in a scratch file in the target repo at
  `<target>/.bottega/<slug>.json`, written with the coordinator's own `sys_os_*`
  tools. It holds the plan/DAG + spine tags and, per slice, `{session
  conversation_id, worktree, branch, base SHA, status, changed_files,
  handbacks[]}`, plus the integration branch and its current HEAD. It is **updated
  after every state transition** — a slice dispatched, a wave integrated, a slice
  merged, a bounce routed, the architect's sign-off.
- **Never committed.** `.bottega/` is runtime scratch (the registry plus the
  `.bottega/wt/<id>` worktrees) and is **gitignored in the target repo** — it is
  never part of the PR. The coordinator adds the ignore on a fresh run if it is
  missing.
- **Resume, not restart.** On (re)start the coordinator loads the registry and
  **reconciles it against git ground truth** (integration HEAD, which `slice/*`
  branches and worktrees exist, which slices are already merged), reclassifies each
  slice into one state, and resumes the wavefront from the recomputed ready set.
  An interrupted or crashed run is recoverable: a slice already merged is **done**,
  one with a commit not yet merged is **awaiting-integration** (it goes straight to
  integrate-wave, never re-dispatched), and one with no commit is **ready** for
  (re)dispatch — so nothing is double-run or left stuck.

## Integration branch and worktrees (the mechanism)

The team carries one feature across roles using omnigent idioms — declared
sub-agents over `sys_session_send`, first-class git worktrees, and the
coordinator-owned JSON registry.

All worktrees of one repository share a single object database and ref store, so a
commit on any branch is immediately visible to a worktree that checks it out.
Git's one constraint — a branch is checked out in **one worktree at a time** — is
satisfied here because **each slice has its own branch** `slice/<id>`, so a wave's
worktrees coexist in parallel. Every wave branches its slice worktrees off the
**current integration HEAD**, so each slice already contains every prior merged
slice.

```
# once per feature — create the integration branch
git -C <target> branch bottega/<slug> <base_commit>

# per ready slice in a wave — a worktree on its OWN branch, off integration HEAD
git -C <target> worktree add .bottega/wt/<id> -b slice/<id> <integration-HEAD-sha>

# after the wave — integrate-wave merges each slice branch into the integration
# branch one at a time, re-greening the gates after each merge (a mechanical merge;
# anything needing new code bounces back to the owning slice's session)
```

The coordinator verifies each fresh worktree with `git -C <wt> rev-parse HEAD`
against the registry's recorded HEAD. **integrate-wave** is owned by the
coordinator/integrator (not the architect — separation of duties); it detects
cross-slice duplication and routes the cleanup to the owning slice, never editing
source itself.

## Stack support — TypeScript and Python

The coordinator detects the **target project's** stack at planning and prefers the
project's own scripts, falling back to defaults:

| Stack | Detected by | tests | lint | typecheck | coverage (optional) | mutation + DRY (architect, mandatory) |
|-------|-------------|-------|------|-----------|---------------------|----------------------------------------|
| **TypeScript / JS** | `package.json` | `npm test` / `vitest run` / `jest` | `eslint` | `tsc --noEmit` | c8 | Stryker / jscpd |
| **Python** | `pyproject.toml` · `setup.py` · `requirements.txt` | `pytest` | `ruff` (or flake8) | `mypy` (or pyright) | pytest-cov | mutmut or cosmic-ray / a duplication detector |

Coverage is included only when the project already configures it. **Mutation and
cross-slice DRY are not optional** — the architect runs them over the whole
assembled feature even when the project ships no such tool, installing a
stack-appropriate one. The detected stack + exact gate commands are recorded in the
registry and passed into every worker; workers do not re-detect.

### Prerequisites
- **omnigent** installed, plus the worker CLIs on PATH: `claude`
  (specifier / refactorer / architect) and `codex` (coder). Install + log in via
  `omnigent setup`. Without `codex` there is no coder, so the pipeline cannot run;
  without `claude` there is no specifier, refactorer, or architect.
- **For a Python target:** `python` + `pytest` (and `ruff` / `mypy` if you want
  those gates).
- **For a TypeScript target:** `node` + `npm`; run `npm install` in the target so
  `vitest` / `tsc` are present.

## Sample target projects

Two minimal targets under `examples/`, each shipping a passing baseline test and
one **deliberately failing** test — the pipeline's red→green starting point:

- [`examples/py-sample`](./examples/py-sample) — Python; `pytest` → 1 passed
  (`add`), 1 failed (`multiply`, the target slice).
- [`examples/ts-sample`](./examples/ts-sample) — TypeScript; `npm test` → 1
  passed (`adds`), 1 failed (`multiplies`, the target slice).

Each sample already gitignores `.bottega/`, so the coordinator's runtime registry
and worktrees never show up in the target's working tree.

## Run

```
omnigent setup         # one-time per machine: CLI + login per harness
omnigent run bottega/  # launch the coordinator
```

Then give it a decently-written **PRD/spec** for a feature against a target project
(e.g. "add `multiply` to the py-sample so its failing test passes"). Assuming the
PRD is decent, the coordinator runs **fully automatically, with no mid-process
human stop**: it detects the stack, asks the specifier for a spec + proposed
boundaries, decomposes the work into a DAG, runs the spine-first wavefront wave by
wave (integrating each wave onto the integration branch), has the architect verify
the whole feature, and **opens one PR for you to merge** — it never merges, and
there is no auto-merge.
