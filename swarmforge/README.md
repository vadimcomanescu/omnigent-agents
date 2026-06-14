# swarmforge — ralph-style coding pipeline for omnigent

**swarmforge** adapts [unclebob/swarm-forge](https://github.com/unclebob/swarm-forge)
into a self-contained omnigent team. It keeps swarm-forge's idea — a fixed,
single-responsibility role pipeline (specifier → coder → refactorer → architect)
with strict per-role ownership, branch+commit handoffs, and two human gates — and
replaces the part that doesn't scale: **one long-lived agent per role driving a
whole feature in a single growing context.** That overflows on any non-trivial
feature. swarmforge instead runs **ralph-style**: a conductor decomposes the
approved spec into small vertical slices and spawns a **fresh, scoped worker per
slice**, one at a time, holding the long-horizon memory itself.

The conductor writes no code and never merges. A human approves the plan, and a
human merges the one PR.

## Pipeline

```
                 feature request
                       │
            ┌──────────▼───────────┐
            │  conductor (claude-  │  detects stack, owns the registry +
            │  sdk) — writes no    │  feature branch, decomposes into slices
            │  code, never merges  │
            └──────────┬───────────┘
                       │ dispatch (fresh session)
            ┌──────────▼───────────┐
            │ specifier (claude)   │  spec + acceptance tests (FAILING) +
            │                      │  ordered one-shot-sized slice list
            └──────────┬───────────┘
                       │
         ╔═════════════▼═══════════════╗
         ║   HUMAN GATE 1 — approve     ║   spec + slice plan shown; STOP
         ╚═════════════┬═══════════════╝
                       │
        ┌──────────────▼───────────────┐   the ralph loop, per slice, in order
        │  for slice i in slices:        │
        │    fresh coder (codex) ───────┐│  implement ONLY slice i to green
        │    fresh refactorer (claude) ─┤│  clean up slice i, gates green
        │    conductor updates registry ┘│  head commit, slice done, next
        └──────────────┬───────────────┘
                       │ after the last slice
            ┌──────────▼───────────┐
            │  conductor opens the │  pushes feature branch, ONE PR
            │  ONE PR              │
            └──────────┬───────────┘
                       │ dispatch (purpose: review)
            ┌──────────▼───────────┐
            │  architect (pi)      │  full gate run over the whole feature;
            │                      │  SIGN-OFF or BOUNCE (→ loop slice back)
            └──────────┬───────────┘
                       │ on sign-off
         ╔═════════════▼═══════════════╗
         ║   HUMAN GATE 2 — merge       ║   human merges the PR; conductor
         ╚═════════════════════════════╝   NEVER merges
```

Each role runs in its **own git worktree** across vendors (claude / codex /
claude / pi over the four roles), so the coder's output is always cleaned and
verified by a different vendor than wrote it.

## Roles

| Role | dir | harness / vendor | Owns | Does Not Own |
|------|-----|------------------|------|--------------|
| **specifier** | `agents/specifier` | claude-native | externally-visible behavior spec, acceptance criteria / Gherkin, the **failing acceptance tests**, and the **ordered slice decomposition** (one-shot-sized slices) | implementation, refactors, design rulings, doing the slices |
| **coder** | `agents/coder` | codex-native (`yolo: true`) | TDD implementation of **ONE** approved slice until its acceptance + unit tests pass | spec authorship, structural redesign, quality gates as polish, more than one slice |
| **refactorer** | `agents/refactorer` | claude-native | structure-preserving cleanup of the just-coded slice; makes test / lint / typecheck gates green | adding or altering behavior, redesigning module boundaries, future slices |
| **architect** | `agents/architect` | pi | high-level design, module boundaries, dependency direction, **final verification** (full gate run over the assembled feature) + sign-off/bounce | writing feature code, rewriting slices, merging |

Each role prompt carries explicit `## Owns` / `## Does Not Own` sections (the
swarm-forge mechanic), an instruction to work **only the single slice handed
in**, and a hand-back contract (new HEAD commit, what it did, concerns,
ready-for-next).

## The ralph-style slice decomposition — and why

This is the whole point of the adaptation.

- **Decompose, don't marathon.** The conductor splits the approved spec into
  small **vertical slices** — one acceptance behavior each — sized so a fresh
  worker can implement *and* test it to green in a single context window. If a
  slice still looks too big, it is split further before dispatch. "Small enough
  to one-shot" is the invariant.
- **A fresh session per slice.** Every dispatch uses a new, slice-specific
  `title`. In omnigent, a new `(agent, title)` pair on `sys_session_send` spawns
  a clean worker session; reusing a title would *continue* a thread. swarmforge
  never reuses a worker's title across slices and never continues a worker from a
  previous slice — that would re-grow the very context it is bounding. Workers
  stay ephemeral and small.
- **Memory lives in the conductor.** The conductor keeps a small registry
  (current slice, ordered slice list, feature branch, current HEAD, per-slice
  notes) and feeds each fresh worker only its slice-sized context. The conductor
  is the single source of continuity; no worker carries the feature's history.
- **One slice at a time.** The loop is sequential. The conductor never hands a
  whole feature to one worker and never runs two slices in parallel.

Why it matters: swarm-forge's single-context-per-role design hits
`context_length_exceeded` on real features. Bounding each worker to one slice
keeps every worker comfortably inside its window, and pushing the long-horizon
state into the conductor's registry is what makes that possible.

## Handoff protocol

Replaces swarm-forge's tmux `send-keys` + sequence-numbered text-file queue with
omnigent idioms.

- **One feature branch** carries the whole feature: `swarmforge/<slug>`.
- **The conductor owns a registry** at `<target>/.swarmforge/<slug>.json`
  (current slice index, ordered slice list, feature branch, base + current HEAD,
  per-slice handoff notes), written with the conductor's own `sys_os_*` tools.
  This is the durable analogue of swarm-forge's `.swarmforge/` queue and the home
  of all long-horizon memory.
- **Each dispatch carries only the slice's context:** worktree path, feature
  branch + upstream HEAD commit, the slice's spec excerpt + acceptance test, the
  role's Owns/Does-Not-Own boundary, and the stack + gate commands. The worker
  `cd`s into its worktree, commits onto the feature branch, and reports back
  `{new HEAD commit, what it did, concerns, ready-for-next}`.

### Cross-worktree branch handoff (the mechanism, and why it works)

All worktrees of one repository share a single object database and ref store, so
a commit made on `swarmforge/<slug>` from worker A's worktree is immediately
visible to any other worktree that checks that branch out. Git's only constraint
is that a branch can be checked out in **one worktree at a time** — fine here,
because the loop is sequential. Per dispatch the conductor (via `sys_os_shell`):

```
# once per feature — create the branch without checking it out anywhere
git -C <target> branch swarmforge/<slug> <base_commit>

# per worker — drop the previous worktree, add a FRESH one on the shared branch
git -C <target> worktree remove --force <prev_wt> 2>/dev/null || true
git -C <target> worktree add <wt_path> swarmforge/<slug>
#   ^ <wt_path> now contains EVERY prior worker's commit (shared refs/objects)
```

The freshly added worktree already holds the previous worker's commit — that *is*
the handoff. The conductor verifies it with `git -C <wt_path> rev-parse HEAD`
against the registry's recorded HEAD. (See "Smoke test" in the PR for a runnable
proof: a commit made in worktree A appears in a fresh worktree B on the same
branch.)

## Stack support — TypeScript and Python

The conductor detects the **target project's** stack before dispatching coders
and prefers the project's own scripts, falling back to defaults:

| Stack | Detected by | tests | lint | typecheck | coverage / mutation |
|-------|-------------|-------|------|-----------|---------------------|
| **TypeScript / JS** | `package.json` | `npm test` / `vitest run` / `jest` | `eslint` | `tsc --noEmit` | c8 / stryker |
| **Python** | `pyproject.toml` · `setup.py` · `requirements.txt` | `pytest` | `ruff` (or flake8) | `mypy` (or pyright) | pytest-cov / mutmut |

The detected stack + exact gate commands are recorded in the registry and passed
into every worker; workers do not re-detect.

### Prerequisites
- **omnigent** installed, plus the worker CLIs on PATH: `claude`
  (specifier/refactorer), `codex` (coder), `pi` (architect). Install + log in via
  `omnigent setup`. Without `codex` there is no coder and the pipeline cannot
  run; without `pi` slices still run but the architect's final verification is
  skipped.
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

## Run

```
omnigent setup            # one-time per machine: CLI + login per harness
omnigent run swarmforge/  # launch the conductor
```

Then describe a feature against a target project (e.g. "add `multiply` to the
py-sample so its failing test passes"). The conductor detects the stack, asks the
specifier for a spec + slice plan, **stops at Human Gate 1** for your approval,
runs the ralph loop slice by slice, opens one PR, has the architect verify it,
and **stops at Human Gate 2** for you to merge.

## How it maps to / differs from upstream swarm-forge

**Preserved**
- Fixed, single-responsibility role pipeline (specifier → coder → refactorer →
  architect).
- Per-role `## Owns` / `## Does Not Own` ownership boundaries.
- Branch + commit handoff between roles.
- Two human gates: approve the spec, merge at the end.

**Replaced with omnigent idioms**
- tmux `send-keys` + terminal watchdogs + a bespoke text-file queue → a declared
  omnigent team: `sys_session_send` + inbox for the wire, first-class git
  worktrees, and a conductor-owned JSON registry.
- A fixed roster of always-on role processes → fresh, scoped worker sessions the
  conductor spawns on demand.

**Added (swarm-forge has no equivalent)**
- **Ralph-style slice decomposition with a fresh worker per slice**, and
  **long-horizon memory in the conductor's registry** rather than in any worker's
  context — so workers never overflow their context window.
- A cross-vendor pipeline (claude / codex / claude / pi across the four roles) so
  the coder's implementation is always reviewed and cleaned by other vendors.

## Attribution

Orchestration pattern adapted from **swarm-forge** by Robert C. Martin
(unclebob): https://github.com/unclebob/swarm-forge. swarmforge reimplements the
*idea* (role pipeline, ownership boundaries, branch handoff, human gates) on
omnigent; none of swarm-forge's bash/tmux code is used.
