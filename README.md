# omnigent-agents

A reusable library of [omnigent](https://github.com/omnigent-ai/omnigent) agent
teams. Each top-level directory is one self-contained agent (or "team of
agents") you can launch with `omnigent run <dir>/`. Git is the sync layer — clone
or pull this repo on any device to get the same teams.

## Teams

| Team | What it's for |
|------|---------------|
| [`duetta`](./duetta) | **Duetta, two-headed brainstorming.** A port of Omnigent's bundled Debby example, renamed and changed so the GPT head uses the local Codex CLI harness instead of the OpenAI Agents SDK. |
| [`concordia`](./concordia) | **Concordia — mixture-of-experts panel.** Asks one question, in parallel, to Claude Opus 4.8 + GPT-5.5 + GLM 5.2, then a fixed Opus-4.8 synthesizer blinds the drafts, builds an evidence-weighted claim table, flags "unverified consensus", runs a gated different-vendor verifier, and returns one cross-checked answer. For hard reasoning / research / high-stakes questions where one model isn't enough. |
| [`bottega`](./bottega) | **bottega — a software development team.** Give it a decent PRD and it runs **fully automatically**: a team lead decomposes the PRD into a dependency DAG of small vertical slices, lands shared contracts first (spine-first), then runs the independent slices in **parallel waves** — each slice a fresh worker session in its own git worktree (specifier → coder, who TDDs the whole slice in one session → refactorer), so no worker overflows its context. Each wave merges into one integration branch; a final architect pass verifies the **whole assembled feature** (gates → mutation → DRY) before the single PR. Only the coder writes feature code (codex), and it's reviewed/verified by a different vendor (refactorer + architect, both claude). The lean coordinator loads its methodology from **on-demand skills** and keeps **durable, restorable** memory in a per-target registry, so an interrupted run resumes instead of restarting. There is **no mid-process human gate** — from spec-division through wavefront → integrate → verify it runs unattended and opens **one PR** for a human to merge (the team lead never merges; no auto-merge). TypeScript + Python targets. |

## Layout

```
omnigent-agents/
├── duetta/          # config.yaml + agents/<name>/ + skills/debate/
├── concordia/        # config.yaml + agents/<name>/config.yaml + its own README
├── bottega/       # config.yaml + agents/<name>/ + skills/<name>/ + examples/ + README
└── README.md
```

Every team is a **self-contained** omnigent agent directory (`config.yaml` plus an
`agents/` subtree). omnigent has no cross-directory `include`/`import`, so teams
are independent by design — shared pieces are copied, not linked.

## Run a team

```
git clone https://github.com/vadimcomanescu/omnigent-agents
cd omnigent-agents
omnigent setup            # one-time per machine: log in per harness (claude / codex / pi)
omnigent run concordia/   # launch a team by path
```

See each team's own README for team-specific prerequisites.

## Use across your devices

`git` is the sync. On each device: `git clone` (first time) or `git pull` (to
update), then `omnigent run <team>/`.

What git does **not** carry — set up once per machine:
- Each harness's CLI + login (`omnigent setup`); auth tokens are local
  (`~/.omnigent/auth_tokens.json`), not synced.
- Model access / credits for whatever a team pins (e.g. `concordia` needs Claude
  Opus 4.8, GPT-5.5, and OpenRouter DeepSeek-V4-Pro **with credits**).
- Any stopgap patch a team documents (e.g. `concordia`'s pi leg needs omnigent
  PR #48 until it merges — see `concordia/README.md`).

Optional "launch by name from any device + roaming sessions": run one
self-hosted omnigent server and pre-register every team at startup —
`omnigent server start --agent concordia/ --agent <next-team>/ ...` — then
`omnigent login <url>` + `omnigent run --server <url> <agent>` from any device.
The server centralizes definitions + sessions, not execution: harnesses still
run on whichever machine hosts, so the per-device setup above still applies.

## Add a team

Drop a new self-contained agent directory (or a single agent YAML) at the repo
root, add a row to the Teams table above, commit, and push. Launch it with
`omnigent run <new-team>/`.
