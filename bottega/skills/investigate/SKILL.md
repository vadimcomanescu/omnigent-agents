---
name: investigate
description: Delegate read-only investigation, debugging, audit, search, or code-understanding tasks to sub-agents and synthesize only from their structured reports. In bottega, load it at DAG construction (to ground real contract edges) and on a bounce (to attribute a failure to its owning slice).
---

# investigate — delegated read-only work

Use for any read-only task: reading the target repo to ground contract edges,
attributing a failure to a slice, debugging, audit, search, code understanding,
or answering a repository-specific technical question.

## Procedure
1. Decompose the question into one or more bounded investigation tasks. Prefer
   two independent lenses for ambiguous or high-stakes questions.
2. Dispatch each task to a roster role with `purpose: "explore"`:
   `sys_session_send(agent=<role>, title="explore-<task_slug>",
   args={purpose: "explore", input: "<question + exact scope + evidence
   requested>"})`. Use a task-based title such as `explore-contract-edges` or
   `explore-mutation-survivor`, never the raw role name. A read-mostly role fits
   best — the specifier for contract / boundary recon at planning, the architect
   for design or failure-attribution questions. Tell the worker to edit nothing
   and to return file, command, or line evidence. Emit these `sys_session_send`
   calls in the SAME turn — do not end a turn having only said you will dispatch.
3. End your turn AFTER the dispatch tool calls are in flight (never before). Do
   not inspect files, logs, or repo contents yourself while the workers run.
4. When workers finish, collect their reports with `sys_read_inbox`. Synthesize
   only from those inbox-delivered reports. Use `sys_session_get_history` only to
   debug an empty or unclear worker result; if reports conflict or are
   incomplete, dispatch a follow-up `explore` task rather than resolving it from
   your own direct inspection.

## In bottega specifically
- **At DAG construction** (slice-decompose-to-dag): dispatch explore tasks to
  read the target repo so each slice's `produces` / `consumes` reflect the actual
  interfaces in the code — real contracts, not guessed edges.
- **On a bounce** (architect-verify): dispatch an explore task to pin a surviving
  mutant or a duplication cluster to the slice that introduced it, so the fix routes
  to the right role-session — a surviving mutant to that slice's CODER session, a
  duplication cluster to its REFACTORER session.

## Notes
- The coordinator may use its own tools only to create task packets, maintain the
  registry, or check deterministic status. It must not answer the substantive
  question from its own deep file reads or shell output.
- Keep each task scope narrow enough that a worker returns a concise report with
  evidence. Split broad investigations into parallel subtasks.
