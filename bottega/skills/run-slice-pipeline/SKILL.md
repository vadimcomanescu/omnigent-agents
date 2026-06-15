---
name: run-slice-pipeline
description: Load per slice — the COORDINATOR's 3-role dispatch sequence (specifier → coder → refactorer, SEPARATE sessions, a handback to the coordinator between each) that drives ONE vertical slice from a failing acceptance test to refactored green in a single worktree. Load for every slice the wavefront dispatches.
---

# run-slice-pipeline — one slice, one worktree, the whole way to green

The slice is the unit of delegation. This is the role sequence for ONE slice, in
ONE worktree. The COORDINATOR runs it as THREE SEPARATE role-sessions in sequence,
staying in control between each: it dispatches the specifier, waits for the
handback, dispatches the coder, waits, dispatches the refactorer. The three roles
are different agents on different harnesses — so they are DIFFERENT sessions; one
session NEVER runs the whole specifier → coder → refactorer pipeline. The
red → green → refactor inner loop is the CODER's alone, inside the coder's own
session (step 2).

## The sequence (one slice — the coordinator dispatches each, in order)
1. **specifier** (session A) writes (or confirms) the FAILING acceptance test for
   THIS slice and confirms it fails for the right reason — the behavior is absent,
   not a typo or harness mistake — then hands back to the coordinator.
2. **coder** (session B) TDD-implements the ENTIRE slice in ONE persistent session:
   red -> green -> refactor as an INNER loop — write a small failing test, write
   the minimum code to pass it, clean up, repeat — committing on green. The coder
   does the whole slice itself. It never carves the slice into sub-tasks farmed
   out to separate fresh sessions, and it never starts a fresh session per micro
   step. One slice in the coder's ONE session; the micro-loop lives inside it. Then
   it hands back to the coordinator. (This one-session-with-inner-loop rule applies
   to the CODER only — NOT to the specifier or refactorer.)
3. **refactorer** (session C) does structure-preserving cleanup on that slice and
   adds coverage / property tests where they pay. No new behavior; the acceptance
   and unit tests that passed must still pass unchanged. Then it hands back.

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

## Feedback routes to the role that owns the fix
While a slice is in flight, feedback on it routes BACK to the RELEVANT role's
session for that slice — an architect bounce or a refactorer flag about
IMPLEMENTATION goes to the slice's CODER session; a cleanup issue goes to its
REFACTORER session. Continue the role-session that already holds that work's
context, never a fresh one per fix. The dispatch that carries feedback must still
restate the CURRENT worktree path and expected HEAD: an earlier worktree may have
been removed, so the session re-enters a freshly-added worktree before touching
files. A DIFFERENT role, or a DIFFERENT slice, is a different session.

## Circuit-breaker (recovery only — not the default)
Reset a stuck ROLE-session (usually the coder's) to a FRESH session that re-reads
the durable state — the acceptance test, the current diff, and the spec — ONLY when
that session is thrashing or its context has rotted or been polluted: N consecutive
failures on the SAME test with no progress, or budget burned with no diff to show
for it. This is recovery from a stuck session, not how slices normally run. The
normal case is the coder's ONE durable session carrying its implementation from red
to refactored green, bracketed by the separate specifier and refactorer sessions.
