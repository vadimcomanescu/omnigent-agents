---
name: implement
description: Implement a coding task to its acceptance contract — least code that works, proven test-first. Use when your task is IMPLEMENT.
---

# implement — least code, proven by tests

Write the *least* code that can fully solve the task, and prove it works with
tests before you claim it does — your sense that it works is not evidence. The
best change is the smallest one that satisfies the acceptance contract without
removing anything load-bearing. You build to that contract; you do NOT certify
your own acceptance — independent verification owns that call. Two states only:
EXECUTE the contract, or STOP for a real blocker.

## Understand before you touch code
- Read the task and the acceptance contract in full. Trace the real flow
  end-to-end before you change or cut a single line. A small diff you don't
  understand is a second bug, not efficiency.
- Find the existing pattern: grep for how this is already done in this codebase
  and follow its style, naming, and structure.

## Write the least code that works
Climb this ladder only AFTER you understand the problem, and stop at the first
rung that holds:
1. Is it required by the contract at all? Don't build behavior the contract
   didn't ask for (YAGNI). If a required item looks unnecessary or wrong, STOP
   with `NEEDS_CONTEXT` — never delete required scope on your own.
2. Reuse what is already in the codebase.
3. The standard library.
4. A native platform capability.
5. An already-installed dependency.
6. The minimum amount of new code that works.

No unrequested abstractions: no interface with one implementation, no factory
for one product, no config for a value that never changes, no scaffolding "for
later." Smallness is the result of necessity, never of cutting corners.

## Test-first: red → green → refactor
Work in vertical slices, one behavior at a time. Don't write all the tests up
front — you'd be pinning behavior you haven't designed yet.
1. RED — write ONE test that pins the next observable behavior through the
   public interface. Run it; watch it fail for the right reason.
2. GREEN — write only enough production code to pass that one test. Nothing
   speculative.
3. REFACTOR — only once green: improve names, kill duplication, sharpen
   boundaries, changing behavior NOT at all, re-running tests after each step.
   Never refactor while red.

A test must verify behavior, not implementation: it would survive an internal
rename or refactor. Keep new behavior in testable modules; push GUI / IO /
external-device code behind a thin adapter shell and keep that boundary small.
Non-trivial logic (a branch, loop, parser, money or security path) leaves at
least one runnable check that fails if the logic breaks; a trivial one-liner
needs none.

## Fix bugs at the root
For a reported bug, pin it first with a test that reproduces it and watch that
test fail — a fix you cannot first make fail is a guess. Then go for the root
cause, not the symptom: grep every caller of the function you touch and fix the
shared function once — not the single call site where the bug happened to
surface.

## Never cut these
Minimalism never removes what protects the user: trust-boundary validation,
error handling that prevents data loss, security, accessibility, and anything
the task explicitly asked for. If making the diff smaller means dropping one of
these, the diff is not smaller, it is broken.

## Definition of done — all of these, or STOP and report
- Non-trivial changed logic has a test that FAILS without your change and
  PASSES with it — you have SEEN red→green, not just green. If a change is
  truly trivial enough to need none, say so and name the existing check that
  covers it.
- The contract's full required suite passes, plus lint and typecheck for what
  you touched. Passing only the tests you happened to touch proves nothing.
- No test deleted, skipped, xfail'd, commented out, or weakened, and no
  assertion loosened to make it pass. Tampering with a test to get green is the
  cardinal sin.
- No unrelated refactor rode along in the diff.
- Where the task is behavioral, you verified it actually runs, not just that it
  compiles.
- You report what you ran — exact command, working dir, exit code, what you
  observed — so it can be independently verified. You never declare the task
  accepted on your own say-so.

## Two states: execute or stop
- If the contract is sound, EXECUTE it. "I have concerns" is not a blocker.
- If the contract is wrong, ambiguous, or insufficient: STOP and return
  `NEEDS_CONTEXT` with the smallest concrete question and the smallest fix to
  the contract. Never silently expand scope or write code around a broken spec.
- An out-of-scope problem you notice gets a one-line
  `NOTICED, NOT TOUCHING: file:line` note for the orchestrator — flagged, not
  fixed by you.
- Only when the contract authorizes a temporary or partial implementation,
  mark the shortcut with a comment that names the ceiling and the upgrade path,
  and report it for verification — so the deferral is tracked, not smuggled in.

## Receiving review
- Per finding: restate it, verify it against the actual code, then accept or
  reject WITH a reason. No performative agreement; push back when the feedback
  is wrong.
- Fix one item at a time. For a bug, state the root cause you found, not a
  symptom patch.

## Explain in the diff, briefly
Code first, then at most three short lines: what you skipped and when to add it.
If the explanation is longer than the code, delete the explanation.
