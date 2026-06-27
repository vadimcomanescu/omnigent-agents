---
name: cross-review
description: Verify an implementer's PR with two independent different-vendor sub-agents — a QA verifier that runs it to prove acceptance, then a reviewer that judges the diff — and loop blocking issues back to the implementer until clean.
---

# cross-review — independent verification

The implementer never signs off on its own work. Two independent roles do, each
a different vendor than the builder, each returning a structured report rather
than a transcript anyone reads through:
- **QA verifier** (`purpose: qa-verify`) checks the PR out and RUNS it to prove
  the acceptance contract holds — proof of behavior.
- **Reviewer** (`purpose: review`) reads the diff against the contract to judge
  code health — correctness, security, simplification, architecture,
  test-integrity. Reads only; never runs, never edits.

QA proves it does what was asked; review judges whether it was built well. A PR
can pass one and fail the other, so both gate the merge.

## Procedure
1. Get the task's diff — `sys_os_shell("gh pr diff <pr>")` (or
   `git -C .worktrees/<task_id> diff main...HEAD`) — and the PR ref (branch +
   HEAD commit) for QA.
2. Run the deterministic gates first — tests / lint / typecheck via
   `sys_os_shell`. If red, re-dispatch the implementer to drive it green first;
   don't involve QA or the reviewer yet.
3. **Independent QA.** Dispatch a DIFFERENT-vendor sub-agent with
   `purpose: "qa-verify"` to prove acceptance:
   `sys_session_send(agent=<different vendor than the implementer>,
   title="qa-<task_slug>", args={"purpose": "qa-verify", "input": "<the acceptance
   contract> + <the PR ref>. Check it out, RUN it, prove each acceptance
   criterion by observation. Do not edit. Return the proof-of-acceptance
   artifact + a PASS/FAIL/BLOCKED/SKIP verdict."})`. The QA worker's resolved
   vendor MUST differ from the implementer's — the builder never certifies its
   own work. On `FAIL` or `BLOCKED`, route the failing criteria back to the
   implementer (step 5) and loop; do NOT involve the reviewer until QA is `PASS`
   (or `SKIP` for criteria with no runtime surface).
4. **Cross-review.** Dispatch a DIFFERENT-vendor sub-agent with
   `purpose: "review"` (a different vendor than the implementer; ideally also
   different from QA):
   `sys_session_send(agent="claude_code"|"codex"|"pi", title="review-<task_slug>",
   args={"purpose": "review", "input": "<the diff> + <the acceptance contract> +
   <QA's evidence as facts>. Review ONLY against the contract. Report blocking /
   non-blocking / suggestions with file:line. Do not run code. Do not edit."})`.
   Give it the diff as text and QA's evidence as facts — do NOT point it at the
   implementer's worktree, and do NOT pass the implementer's narrative. Fetch the
   inputs and emit the `sys_session_send` call in the SAME turn you decide to act
   — never end a turn having only announced "I'll fetch the diff" with no tool
   call (that dropped turn stalls the run; nothing dispatches and no inbox wake
   arrives). Once a dispatch is in flight, end your turn; collect the
   inbox-delivered report with `sys_read_inbox`. Use `sys_session_get_history`
   only to debug an empty or unclear result.
5. **Route every blocking item back to the implementer.** A QA `FAIL`/`BLOCKED`
   or a critical/major review finding is blocking. Send the concrete fixes to the
   SAME implementer conversation — reuse its original `agent` + `title` (or
   address it by `session_id`) with `purpose: "implement"`, so the worker keeps
   its worktree/branch and updates its existing PR. A new title would spawn a
   fresh worker with no memory of the task. Then loop to step 1 — re-run gates,
   re-QA, re-review the delta.
6. When gates are green, QA is `PASS` (or `SKIP`), AND there are zero blocking
   review findings, the PR passes — mark it ready in the registry (with its PR
   URL) and leave it for the human to merge. maestro does NOT merge it.
7. Cap the loop at three cycles. If blocking items still stand, STOP and escalate
   to the human with the QA artifact and the open review findings. If a finding
   shows the contract itself is the defect, reopen the contract rather than
   grinding code against a broken spec.

## Notes
- **Independence is by RESOLVED vendor, not agent name.** The implementer, the QA
  verifier, and the reviewer should each resolve to a different vendor where the
  roster allows; at minimum QA and review must EACH differ from the implementer.
  Cross-review therefore needs at least two AVAILABLE vendors (per maestro's
  roster preflight). If the roster can't supply a different-vendor QA or reviewer,
  don't dispatch one that can't boot — say so explicitly and pull in the human at
  the plan gate.
- **QA runs it; review reads it.** QA gets the contract + PR ref and executes the
  product in an isolated checkout to prove acceptance. Review gets ONLY the diff +
  contract + QA's evidence-facts, never the worktree or the implementer's
  transcript — the cross-vendor independence is the whole point. Only the
  implementer ever opens or updates a PR, so a stray QA or reviewer edit never
  reaches the deliverable.
- **Test-integrity is split.** Review statically flags a `suspected-tampered-
  assertion @ file:line` (a test rewritten to match broken behavior). That flag
  blocks and routes back to the implementer like any finding; the NEXT QA cycle
  then proves the targeted assertion by mutation (revert the fix → the covering
  test must go red). QA also mutation-tests the change’s core behavior every
  cycle, so a green suite is never acceptance proof.
- Non-blocking issues / suggestions go in the registry as follow-ups; they don't
  block the PR.
