---
name: run-slice-pipeline
description: Load per slice, inside each worker session, to drive ONE vertical slice from a failing acceptance test to refactored green in a single worktree. Load for every slice the wavefront dispatches.
---

# run-slice-pipeline — one slice, one worktree, the whole way to green

The slice is the unit of delegation. This is the role sequence for ONE slice, in
ONE worktree. The grain is deliberate: a session owns a WHOLE slice, and the
small TDD steps are an inner loop WITHIN that session — not separate sessions.

## The sequence (one slice)
1. **specifier** writes (or confirms) the FAILING acceptance test for THIS slice
   and confirms it fails for the right reason — the behavior is absent, not a typo
   or harness mistake.
2. **coder** TDD-implements the ENTIRE slice in ONE persistent session:
   red -> green -> refactor as an INNER loop — write a small failing test, write
   the minimum code to pass it, clean up, repeat — committing on green. The coder
   does the whole slice itself. It never carves the slice into sub-tasks farmed
   out to separate fresh sessions, and it never starts a fresh session per micro
   step. One slice, one session, the micro-loop lives inside it.
3. **refactorer** does structure-preserving cleanup on that slice and adds
   coverage / property tests where they pay. No new behavior; the acceptance and
   unit tests that passed must still pass unchanged.

## What a worker is handed (and only this)
Each worker session for a slice receives exactly:
- the slice id and its behavior spec,
- the contract: `produces` / `consumes` / `touches`,
- the ABSOLUTE worktree path (cd there first),
- the slice branch `slice/<id>` and the base commit SHA it starts from,
- the gate commands (tests / lint / typecheck, coverage if configured),
- the done definition (acceptance + unit tests green; gates green).

A worker is NEVER handed a sibling slice's session or diff. If it needs merged
sibling code, it reads it from its OWN worktree — the worktree was branched off
the current integration HEAD, so every already-merged slice is already present.

## Feedback follows the slice
While a slice is in flight, refactorer or architect feedback on it routes BACK to
that slice's OWN session — continue the session that already holds the slice's
context, never a fresh one per fix. The dispatch that carries feedback must still
restate the CURRENT worktree path and expected HEAD: an earlier worktree may have
been removed, so the session re-enters a freshly-added worktree before touching
files. Only moving to a DIFFERENT slice starts a fresh session.

## Circuit-breaker (recovery only — not the default)
Reset a slice to a FRESH session that re-reads the durable state — the acceptance
test, the current diff, and the spec — ONLY when the in-flight session is
thrashing or its context has rotted or been polluted: N consecutive failures on
the SAME test with no progress, or budget burned with no diff to show for it.
This is recovery from a stuck session, not how slices normally run. The normal
case is one durable session per slice from red to refactored green.
