# swarmforge — a software development team for omnigent

**swarmforge** is a self-contained omnigent team that builds a feature in a
target software project. A **team lead** coordinates four specialist roles —
specifier, coder, refactorer, and architect — each with one fixed
responsibility. The team lead breaks an approved spec into small slices and
dispatches a **fresh worker session per slice**, so each slice runs within a
single context window; the long-horizon state lives in the team lead's own
registry, never in a worker's context.

The team lead writes no code and never merges. A human approves the plan, and a
human merges the one PR.

## Why a fresh worker per slice

A single worker driving an entire feature accumulates context until it overflows
on any non-trivial feature. swarmforge avoids that by bounding each worker to one
slice:

- **Decompose into slices.** The team lead splits the approved spec into small
  **vertical slices** — one acceptance behavior each — sized so a fresh worker
  can implement *and* test it to green in a single context window. If a slice
  still looks too big, it is split further before dispatch. "Small enough to
  one-shot" is the invariant.
- **A fresh session per slice.** Every dispatch uses a new, slice-specific
  `title`. In omnigent, a new `(agent, title)` pair on `sys_session_send` spawns
  a clean worker session; reusing a title would *continue* a thread. swarmforge
  never reuses a worker's title across slices and never continues a worker from a
  previous slice — that would re-grow the very context it is bounding. Workers
  stay ephemeral and small.
- **Memory lives in the team lead.** The team lead keeps a small registry
  (current slice, ordered slice list, feature branch, current HEAD, per-slice
  notes) and feeds each fresh worker only its slice-sized context. The team lead
  is the single source of continuity; no worker carries the feature's history.
- **One slice at a time.** The loop is sequential. The team lead never hands a
  whole feature to one worker and never runs two slices in parallel.

## Pipeline

```
                 feature request
                       │
            ┌──────────▼───────────┐
            │  team lead (claude-  │  detects stack, owns the registry +
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
        ┌──────────────▼───────────────┐   the slice loop, per slice, in order
        │  for slice i in slices:        │
        │    fresh coder (codex) ───────┐│  implement ONLY slice i to green
        │    fresh refactorer (claude) ─┤│  clean up slice i, gates green
        │    team lead updates registry ┘│  head commit, slice done, next
        └──────────────┬───────────────┘
                       │ after the last slice
            ┌──────────▼───────────┐
            │  team lead opens the │  pushes feature branch, ONE PR
            │  ONE PR              │
            └──────────┬───────────┘
                       │ dispatch (purpose: review)
            ┌──────────▼───────────┐
            │  architect (codex)   │  full gate run over the whole feature;
            │                      │  SIGN-OFF or BOUNCE (→ loop slice back)
            └──────────┬───────────┘
                       │ on sign-off
         ╔═════════════▼═══════════════╗
         ║   HUMAN GATE 2 — merge       ║   human merges the PR; team lead
         ╚═════════════════════════════╝   NEVER merges
```

Each role runs in its **own git worktree**. The roles alternate across two
vendors — claude → codex → claude → codex — so the coder's output is always
cleaned and verified by a different vendor than wrote it.

## Roles

| Role | dir | harness / vendor | Owns | Does Not Own |
|------|-----|------------------|------|--------------|
| **specifier** | `agents/specifier` | claude-native | externally-visible behavior spec, acceptance criteria / Gherkin, the **failing acceptance tests**, and the **ordered slice decomposition** (one-shot-sized slices) | implementation, refactors, design rulings, doing the slices |
| **coder** | `agents/coder` | codex-native (`yolo: true`) | TDD implementation of **ONE** approved slice until its acceptance + unit tests pass | spec authorship, structural redesign, quality gates as polish, more than one slice |
| **refactorer** | `agents/refactorer` | claude-native | structure-preserving cleanup of the just-coded slice; makes test / lint / typecheck gates green | adding or altering behavior, redesigning module boundaries, future slices |
| **architect** | `agents/architect` | codex-native (`yolo: true`) | high-level design, module boundaries, dependency direction, **final verification** (full gate run over the assembled feature) + sign-off/bounce | writing feature code, rewriting slices, merging |

Each role prompt carries explicit `## Owns` / `## Does Not Own` sections, an
instruction to work **only the single slice handed in**, and a hand-back
contract (new HEAD commit, what it did, concerns, ready-for-next).

## Handoff protocol

The team carries one feature across roles using omnigent idioms — declared
sub-agents over `sys_session_send`, first-class git worktrees, and a
team-lead-owned JSON registry.

- **One feature branch** carries the whole feature: `swarmforge/<slug>`.
- **The team lead owns a registry** at `<target>/.swarmforge/<slug>.json`
  (current slice index, ordered slice list, feature branch, base + current HEAD,
  per-slice handoff notes), written with the team lead's own `sys_os_*` tools.
  It holds all long-horizon memory.
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
because the loop is sequential. Per dispatch the team lead (via `sys_os_shell`):

```
# once per feature — create the branch without checking it out anywhere
git -C <target> branch swarmforge/<slug> <base_commit>

# per worker — drop the previous worktree, add a FRESH one on the shared branch
git -C <target> worktree remove --force <prev_wt> 2>/dev/null || true
git -C <target> worktree add <wt_path> swarmforge/<slug>
#   ^ <wt_path> now contains EVERY prior worker's commit (shared refs/objects)
```

The freshly added worktree already holds the previous worker's commit — that *is*
the handoff. The team lead verifies it with `git -C <wt_path> rev-parse HEAD`
against the registry's recorded HEAD.

## Stack support — TypeScript and Python

The team lead detects the **target project's** stack before dispatching coders
and prefers the project's own scripts, falling back to defaults:

| Stack | Detected by | tests | lint | typecheck | coverage / mutation |
|-------|-------------|-------|------|-----------|---------------------|
| **TypeScript / JS** | `package.json` | `npm test` / `vitest run` / `jest` | `eslint` | `tsc --noEmit` | c8 / stryker |
| **Python** | `pyproject.toml` · `setup.py` · `requirements.txt` | `pytest` | `ruff` (or flake8) | `mypy` (or pyright) | pytest-cov / mutmut |

The detected stack + exact gate commands are recorded in the registry and passed
into every worker; workers do not re-detect.

### Prerequisites
- **omnigent** installed, plus the worker CLIs on PATH: `claude`
  (specifier/refactorer) and `codex` (coder/architect). Install + log in via
  `omnigent setup`. Without `codex` there is no coder and no architect, so the
  pipeline cannot run; without `claude` there is no specifier or refactorer.
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
omnigent run swarmforge/  # launch the team lead
```

Then describe a feature against a target project (e.g. "add `multiply` to the
py-sample so its failing test passes"). The team lead detects the stack, asks the
specifier for a spec + slice plan, **stops at Human Gate 1** for your approval,
runs the slice loop slice by slice, opens one PR, has the architect verify it,
and **stops at Human Gate 2** for you to merge.

## Attribution

The role-pipeline structure — specifier → coder → refactorer → architect with
per-role ownership boundaries, branch handoff, and two human gates — is adapted
from [swarm-forge](https://github.com/unclebob/swarm-forge). swarmforge
reimplements that structure on omnigent: declared sub-agents instead of tmux,
fresh per-slice worker sessions with the long-horizon state held in the team
lead's registry, and a cross-vendor (claude / codex) pipeline.
