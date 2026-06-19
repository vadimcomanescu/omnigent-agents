---
name: fanout
description: The coordinator's parallel-dispatch primitive — spin K git worktrees off ONE base SHA, dispatch K role-sessions in parallel (one per work item), end the turn, then collect K handbacks from the inbox. slice-wavefront fans out a wave's ready slices; integrate-wave fans out routed cleanup fixes. The coordinator owns it; workers never call it.
---

# fanout — K worktrees off one base, K sessions, K handbacks

The coordinator's primitive for doing K independent things at once. Everything that
runs more than one worker in parallel goes THROUGH here, so the worktree / dispatch /
collect mechanics live in ONE place rather than being re-inlined per caller.
slice-wavefront calls it to advance a wave's ready slices; integrate-wave calls it to
re-dispatch several routed cleanup fixes at once.

## K is an upper bound, not a target
A degenerate fan-out (one ready item) is just the sequential case at K=1 — same
steps. The caller's width policy sets the cap; never widen past genuinely independent
items.

## 1. One base SHA
Resolve the base commit ONCE — the current integration HEAD for a slice wave — and
branch EVERY worktree off that SAME sha, so the K items are truly parallel from a
known shared start.

## 2. Spin K worktrees (absolute paths, `git -C`)
For each item, add a worktree on its own branch off the base sha, using absolute
paths and `git -C` (never the process cwd — see the constitution):
```sh
git -C "$TARGET_ROOT" worktree add "$TARGET_ROOT/.bottega/wt/<id>" -b slice/<id> <base-sha>
```
Record each item's worktree path, branch, and base sha in the registry, and confirm
`git -C "$TARGET_ROOT/.bottega/wt/<id>" rev-parse HEAD` equals the base sha. REUSE a
worktree whose commit already matches the registry; REBUILD one that drifted.

## 3. Dispatch K sessions, then END THE TURN
Emit one `sys_session_send` per item IN THE SAME TURN. A fresh slice-specific
`title` per NEW item opens a clean session; reuse a title (or `session_id`) ONLY to
continue feedback on the SAME item + SAME role. Each `args.input` is item-scoped —
the worktree path, branch + base sha, the slice's spec/contract, gate commands, and
the resolved APS paths — NEVER another item's session or diff. Record each dispatch's
`conversation_id`, set the item's transient RUNNING MARKER (a dispatch never settles a
phase — registry-state), PERSIST, then end the turn. The inbox wakes you; never
busy-poll, never poll with timers.

## 4. Collect K handbacks
Workers finish and wake you via `sys_read_inbox`. For each handback: confirm its
CHANGED-FILES `git diff --stat` is present (ask before advancing if it is missing),
record it in the slice's `handbacks[]` + `last_handback`, and SETTLE the slice to its
next phase on that verified handback (per registry-state), then PERSIST. Cancel a dark, runaway, or superseded worker with
`sys_cancel_task(task_id=<conversation_id>)`.

## Width and the dispatch cap
A bounded `max_dispatches_per_turn` (the spawn guardrail, ~5) caps a single turn's
fan-out. If a wave has more ready items than the cap, dispatch up to the cap this
turn and fan out the remainder next turn — the registry's phases make the leftover
items obvious on the next pass.
