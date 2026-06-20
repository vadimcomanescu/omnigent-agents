# maestro

**Multi-agent coding orchestrator (tech lead).** A fork of Omnigent's bundled
[`polly`](https://github.com/omnigent-ai/omnigent/tree/main/examples/polly)
example, renamed for independent divergence in this repo.

maestro is the tech lead, not a coder. It breaks a goal into pieces and
delegates **every** code/test change, real investigation, and review to three
coding sub-agents, each running in its own git worktree:

- `claude_code` — Claude Code CLI harness. Primary implementer for multi-file /
  refactor / test-writing work. Watchable / take-over-able from the UI.
- `codex` — Codex CLI harness. Primary implementer for narrow, well-scoped
  changes. Watchable / take-over-able from the UI.
- `pi` — headless multi-model worker; the review / explore specialist, and the
  only worker that can run any gateway model.

Each implementer opens its **own PR**; a **different-vendor** sub-agent
cross-reviews the diff (diff + contract only, never the worktree). maestro
writes no code itself and **never merges** — the human merges the PR.

## What maestro does directly

Only non-code authoring: docs / Markdown / text edits and authoring its own
skills (into `maestro/skills/`). Anything touching source or tests — even a
one-line change — is delegated to a sub-agent.

## Skills

`maestro:fanout`, `maestro:cross-review`, `maestro:investigate` (namespaced by
the bundle `name:`).

## Run

```
omnigent run maestro/
```

Needs the `claude`, `codex`, and `pi` CLIs on PATH. Cross-vendor review needs
at least two available vendors — with fewer, maestro flags it and pulls in the
human at the plan gate.

## Fork provenance (drift tracking)

Forked from omnigent `examples/polly` at commit `ed383bc` (2026-06-18,
"polly: co-sign worker commits as omnigent-ci[bot]"; omnigent repo HEAD
`2c93752` at fork time). omnigent has no cross-repo import, so this is a hard
copy — to pull upstream fixes later, diff that path against this directory.

Name migration applied on fork (`polly` → `maestro`), verified zero residual
`polly` tokens:

- bundle `name:` and every self-reference in the orchestrator and worker
  prompts (`You are maestro`, "dispatched by the maestro", etc.);
- skill-authoring path `examples/polly/skills/` → `maestro/skills/`;
- registry `.polly/registry.json` → `.maestro/registry.json`;
- fan-out branch prefix `polly/<task_id>` → `maestro/<task_id>`;
- skill namespace `polly:*` → `maestro:*` (derived automatically from `name:`).

Framework identifiers are intentionally NOT renamed: guardrail policy paths
(`omnigent.inner.nessie.policies.*`), the `Co-authored-by: omnigent` commit
trailer, and harness names (`claude-sdk`, `claude-native`, `codex-native`,
`pi`).

Discipline kept verbatim from polly (the whole point of the pattern):
orchestrator-writes-no-code, cross-vendor review, one-PR-per-task,
human-merges-only, and the roster preflight.
