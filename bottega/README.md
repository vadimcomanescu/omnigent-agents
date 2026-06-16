# bottega — a software development team for omnigent

**bottega** is a self-contained omnigent team that builds a feature in a target
software project. A **coordinator** (team lead) leads four specialist roles —
specifier, coder, refactorer, and architect — each with one fixed
responsibility. The coordinator decomposes a **decent PRD** into a **dependency
DAG of small vertical slices**, lands the shared **spine** first, then drives the
independent slices in **parallel waves**, assembling each wave onto one
**integration branch** and finishing with a whole-feature architect verification.

The coordinator writes no code and never merges. The input is a **decent PRD**;
from there bottega runs **fully automatically** — PLAN → BOOTSTRAP → BUILD → VERIFY
→ one PR — with **no mid-process human gate**, and opens **one PR** at the end for a
human to merge (it never merges; there is no auto-merge). The verbose procedures
live in **on-demand skills** the coordinator loads per stage; the **team-wide
invariants** live in one **`constitution`** skill every role loads at startup. Each
slice's acceptance is driven by the **[acceptance-pipeline-kit](https://github.com/vadimcomanescu/acceptance-pipeline-kit)**
(APS): the specifier authors a Gherkin `.feature` and generates a failing
acceptance entrypoint, the coder drives it green, and the architect runs APS
**acceptance mutation** alongside source mutation at the final gate.

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
- **Three role-sessions per slice; the coder owns one of them whole.** For each
  slice the coordinator dispatches three **SEPARATE** role-sessions in sequence —
  specifier, then coder, then refactorer — staying in control between each (they
  are different agents on different harnesses, hence different sessions). Only the
  **coder** runs the entire slice in **one persistent session**: red → green →
  refactor is an **inner loop inside that coder session**, not a fresh session per
  micro-step, and the slice is never carved into sub-tasks farmed to other sessions.
  Review feedback routes **back to that slice's relevant role-session** — the coder
  for an implementation fix, the refactorer for cleanup — never a fresh one.
- **Parallel only across independent slices.** Fresh role-sessions per *new* slice,
  and the K-wide parallelism runs **ACROSS slices** (K slices' pipelines advancing
  at once), never multiple roles in one session — only across slices with no edge
  either way. A degenerate DAG — a pure chain where each slice consumes the previous
  — collapses to one slice per wave, i.e. the sequential loop. Width is an upper
  bound (default conservative, cap ~5), not a target.

## On-demand skills

The methodology is factored into skills the coordinator loads when needed
(auto-discovered from `skills/<name>/SKILL.md`). The **`constitution`** skill is
different: it carries the team-wide invariants and is loaded by **every role** at
startup (each role's `skills/constitution` points to the one bundle-root file), so
no invariant is restated across prompts.

| Skill | When it loads | What it does |
|-------|---------------|--------------|
| **constitution** | every role, at startup | the one home for the team-wide invariants — hub-and-spoke, worktree + absolute-path discipline, commit-on-green, the handback contract, and never opening/merging the PR |
| **slice-decompose-to-dag** | once at planning | spec → right-sized slices tagged `produces`/`consumes`/`touches`; derives the edges and tags the spine |
| **registry-state** | with the wavefront | the single home for the registry schema and the per-slice phase machine (`pending → … → ready_to_integrate → integrated/done`, plus `contract_landed`); how RESUME reclassifies from phase + git + gate |
| **bootstrap-aps** | once, the BOOTSTRAP step (coordinator-run) | verify-or-install the pinned APS toolchain (two Go binaries + a pinned Python 3.12 venv with `aps-kit` + `mutmut`); write `.bottega/aps.lock`; resolve the absolute APS paths |
| **run-slice-pipeline** | per slice, run by the coordinator | dispatches specifier → coder (coder-only TDD inner loop) → refactorer as SEPARATE sessions for ONE slice; holds the dispatch-packet contract and the APS commands each role runs |
| **fanout** | by wavefront / integrate-wave | the parallel-dispatch primitive — K worktrees off one base SHA, K sessions, K handbacks |
| **slice-wavefront** | once, the BUILD loop | integration branch, spine-first, then dependency-ordered parallel waves; holds the width policy; durable + resumable |
| **integrate-wave** | after each wave | accept only `ready_to_integrate` slices, detect cross-slice duplication, merge each branch one at a time, re-green the gates |
| **architect-verify** | once, VERIFY | gates → source mutation → cross-slice DRY → APS acceptance mutation over the whole feature; SIGN-OFF or BOUNCE; holds the bounce-loop cap |
| **pr-assemble** | once, after sign-off | the coordinator opens the ONE PR and stops; a human merges |
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
                       │ PLAN: slice-decompose-to-dag (+ specifier, + investigate)
            ┌──────────▼───────────┐
            │      specifier       │  behavior spec + proposed boundaries (planning);
            │                      │  per slice: Gherkin .feature + FAILING acceptance
            │                      │  entrypoint (generated by the APS kit)
            └──────────┬───────────┘
                       │ BOOTSTRAP: bootstrap-aps (coordinator-run, once) — pin the
                       │ APS toolchain + venv, write .bottega/aps.lock, resolve paths
                       │ BUILD: slice-wavefront — automatic, no human gate
   ┌───────────────────▼─────────────────────────────────────┐
   │  spine first (sequential): land the shared contracts     │
   │  ──────────────────────────────────────────────────────  │
   │  wave loop until the DAG drains (fanout = the primitive): │
   │    ready set = independent slices whose producers merged  │
   │    spin K worktrees off the current integration HEAD      │
   │    K slices in parallel — per slice YOU dispatch, in      │
   │    control between each, 3 SEPARATE role-sessions:        │
   │      specifier →(you)→ coder (drives APS entrypoint green)│
   │      →(you)→ refactorer                                   │
   │    integrate-wave: accept only ready_to_integrate, detect │
   │        dup, merge each slice/* one at a time, re-green    │
   └───────────────────┬─────────────────────────────────────┘
                       │ DAG drained → VERIFY: architect-verify
            ┌──────────▼───────────┐
            │      architect       │  gates → source mutation → cross-slice DRY →
            │                      │  APS acceptance mutation; SIGN-OFF or BOUNCE
            └──────────┬───────────┘
                       │ on sign-off → PR: pr-assemble
         ╔═════════════▼═══════════════╗
         ║   open ONE PR → human merges ║   coordinator opens one PR and STOPS;
         ╚═════════════════════════════╝   a human merges — it NEVER merges (no auto-merge)
```

Each slice runs in its **own git worktree**. Only the **coder** writes feature
code, and the roles that clean and verify it — refactorer and architect — are
**different agents**, so the implementation is always reviewed by a different
agent than wrote it. (The roster table below shows the concrete vendor split that
makes that review cross-vendor.) On a bounce, the architect attributes each
failure to the owning slice and the coordinator routes the fix back to that slice's
relevant role-session (the coder for an implementation fix) — bounded targeted
passes only, never a re-implementation loop.

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
            dispatch (fresh │          │ dispatch (fresh role-session per slice;
             session) ──────┤          ├────── feedback CONTINUES that slice's
                            ▼          ▼         relevant coder/refactorer session)
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
bounce the coordinator (not the architect) routes the fix back to that slice's
relevant role-session (the coder for an implementation fix).

## Roles

| Role | dir | harness / vendor | Owns | Does Not Own |
|------|-----|------------------|------|--------------|
| **specifier** | `agents/specifier` | claude-native | externally-visible behavior spec + **proposed boundaries** (planning); per slice, the **Gherkin `.feature`** and the **generated FAILING acceptance entrypoint** (APS kit) | implementation, the slice's unit tests, refactors, design rulings, the DAG (the coordinator owns it) |
| **coder** | `agents/coder` | codex-native | TDD implementation of **ONE** whole slice in one persistent session; drives the **generated acceptance entrypoint** + native unit tests green | spec authorship / the `.feature`, structural redesign, quality gates as polish, more than one slice |
| **refactorer** | `agents/refactorer` | claude-native | structure-preserving cleanup of the just-coded slice; makes test / lint / typecheck gates green; coverage / property tests | adding or altering behavior, redesigning module boundaries, other slices |
| **architect** | `agents/architect` | claude-native | high-level design, module boundaries, dependency direction, **final verification** (full gates → **source mutation, killing survivors** → **cross-slice DRY** → **APS acceptance mutation**) + sign-off/bounce | writing feature code, rewriting slices, running integration, merging |

The coder runs on a different vendor than the refactorer and architect, which is
what makes the always-different-agent review **cross-vendor**. Every role loads the
**`constitution`** skill at startup for the team-wide invariants (hub-and-spoke,
worktree + absolute-path discipline, commit-on-green, the handback contract, never
opening/merging the PR), so each prompt carries only its role-specific `## Owns` /
`## Does Not Own` / `## Handoff` — the shared rules are stated once, in the
constitution. The handback leads with **STATUS** + a **CHANGED-FILES** `git diff
--stat`, then the role's own fields.

## Durable + restorable registry

The coordinator's working memory is **durable and restorable** — it writes no
code, so build state cannot live in its context alone.

- **Persisted.** The registry lives in a scratch file in the target repo at
  `<target>/.bottega/<slug>.json`, written with the coordinator's own `sys_os_*`
  tools. Its schema and the per-slice **phase machine** are the single home of the
  **`registry-state`** skill: per slice it records `{phase, per-role session
  conversation_ids, worktree, branch, base SHA, red/green head shas, gate_results,
  last_handback, handbacks[]}`, plus the resolved APS paths, the integration branch,
  and its current HEAD. It is **persisted after every phase transition**.
- **Never committed (except the lock).** `.bottega/` is runtime scratch — the
  registry, the `.bottega/wt/<id>` worktrees, the `.bottega/bin/` APS binaries, and
  the `.bottega/aps-venv` pinned venv — and is **gitignored** via `.bottega/*` +
  `!.bottega/aps.lock`, so only the committed **`aps.lock`** is tracked. The
  coordinator adds the ignore on a fresh run if it is missing.
- **Resume, not restart.** On (re)start the coordinator loads the registry and
  **reclassifies each slice from its persisted phase + git ground truth + gate
  result** — never from mere commit existence (a slice carrying only the specifier's
  RED acceptance commit is `spec_done`, sent to the coder, **not** treated as ready
  to integrate). A running phase is never trusted on resume; it falls back to the
  last completed phase. Then it resumes the wavefront from the recomputed ready set,
  so nothing is double-run or left stuck. **integrate-wave merges only slices in
  `ready_to_integrate`.**

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
# anything needing new code bounces back to the owning slice's coder session)
```

The coordinator verifies each fresh worktree with `git -C <wt> rev-parse HEAD`
against the registry's recorded HEAD. **integrate-wave** is owned by the
coordinator/integrator (not the architect — separation of duties); it detects
cross-slice duplication and routes the cleanup to the owning slice, never editing
source itself.

## Stack support — TypeScript and Python

The coordinator detects the **target project's** stack at planning and prefers the
project's own scripts, falling back to defaults:

| Stack | Detected by | tests | lint | typecheck | coverage (optional) | source mutation + DRY + APS acceptance mutation (architect, mandatory) |
|-------|-------------|-------|------|-----------|---------------------|----------------------------------------|
| **TypeScript / JS** | `package.json` | `npm test` / `vitest run` / `jest` | `eslint` | `tsc --noEmit` | c8 | Stryker / jscpd / `gherkin-mutator` |
| **Python** | `pyproject.toml` · `setup.py` · `requirements.txt` | `pytest` | `ruff` (or flake8) | `mypy` (or pyright) | pytest-cov | `mutmut` (pinned venv) / a duplication detector / `gherkin-mutator` |

Coverage is included only when the project already configures it. **Source mutation,
cross-slice DRY, and APS acceptance mutation are not optional** — the architect runs
all three over the whole assembled feature. The APS acceptance toolchain is pinned by
the BOOTSTRAP step (`bootstrap-aps`) and recorded in `.bottega/aps.lock`; source
mutation is installed stack-appropriately. The detected stack + exact gate commands
are recorded in the registry and passed into every worker; workers do not re-detect.

### Prerequisites
- **omnigent** installed, plus the worker CLIs on PATH: `claude`
  (specifier / refactorer / architect) and `codex` (coder). Install + log in via
  `omnigent setup`. Without `codex` there is no coder, so the pipeline cannot run;
  without `claude` there is no specifier, refactorer, or architect.
- **`uv`** + `curl` on PATH, so the BOOTSTRAP step can create the pinned Python 3.12
  venv and download the APS binaries. The APS kit
  ([acceptance-pipeline-kit](https://github.com/vadimcomanescu/acceptance-pipeline-kit)
  `v0.1.0`) is fetched automatically into `<target>/.bottega/`; you do not pre-install
  it.
- **For a Python target:** `python` + `pytest` (and `ruff` / `mypy` if you want those
  gates).
- **For a TypeScript target:** `node` + `npm`; run `npm install` in the target so
  `vitest` / `tsc` are present.

## Sample target projects

Two minimal targets under `examples/`, each shipping a passing baseline test and
one **deliberately failing** test — the pipeline's red→green starting point:

- [`examples/py-sample`](./examples/py-sample) — Python; `pytest` → 1 passed
  (`add`), 1 failed (`multiply`, the target slice).
- [`examples/ts-sample`](./examples/ts-sample) — TypeScript; `npm test` → 1
  passed (`adds`), 1 failed (`multiplies`, the target slice).

Each sample already gitignores the `.bottega/` runtime scratch (`.bottega/*` +
`!.bottega/aps.lock`), so the registry, worktrees, APS binaries, and pinned venv
never show up in the target's working tree, while the committed `aps.lock` is tracked.

## Run

```
omnigent setup         # one-time per machine: CLI + login per harness
omnigent run bottega/  # launch the coordinator
```

Then give it a decently-written **PRD/spec** for a feature against a target project
(e.g. "add `multiply` to the py-sample so its failing test passes"). Assuming the
PRD is decent, the coordinator runs **fully automatically, with no mid-process
human stop**: it detects the stack, asks the specifier for a spec + proposed
boundaries, decomposes the work into a DAG, **bootstraps the pinned APS toolchain**,
runs the spine-first wavefront wave by wave (each slice driving its generated APS
acceptance entrypoint green, integrating each wave onto the integration branch), has
the architect verify the whole feature (gates → source mutation → DRY → APS
acceptance mutation), and **opens one PR for you to merge** — it never merges, and
there is no auto-merge.
