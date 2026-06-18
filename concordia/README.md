# Concordia — Fusion-style mixture-of-experts agent for omnigent

**Concordia** is a local, self-owned [OpenRouter-Fusion](https://openrouter.ai/docs/guides/routing/routers/fusion-router)
pipeline — harmony from many minds. One task fans out in parallel to three
grounded, model-pinned experts; their drafts are blinded (A/B/C); a **judge**
COMPARES the drafts across five angles; then a fixed **Opus 4.8 @ max**
coordinator SYNTHESIZES one final answer from that comparison.

```
panel (same task, grounded, blinded A/B/C)
  -> JUDGE compares: consensus | contradictions | partial coverage | unique insights | blind spots
  -> COORDINATOR synthesizes the final answer FROM the judge's analysis
```

This mirrors Fusion's division of labour: the judge **compares** the candidate
responses (it does not merge them, vote, grade, or write the answer), and the
calling/coordinator model writes the final answer **from** that comparison. See
the [Fusion router docs](https://openrouter.ai/docs/guides/routing/routers/fusion-router)
and ["Fusion beats frontier"](https://openrouter.ai/blog/announcements/fusion-beats-frontier/).

## Layout
```
concordia/
├── config.yaml            # coordinator + synthesizer: Opus 4.8 @ max, cost advisor OFF
└── agents/
    ├── claude/            # panel expert — Claude Opus 4.8 @ max (grounded)
    ├── codex/             # panel expert — GPT-5.5 @ xhigh (grounded, local codex login)
    ├── pi/                # panel expert — GLM 5.2 via OpenRouter (grounded)
    └── judge/             # Fusion judge — Opus 4.8 @ max, COMPARES the blinded drafts
```

## Pipeline
1. **Fan out (parallel).** The coordinator sends the SAME task verbatim to all
   three experts at once. Each expert is independently grounded
   (`web_fetch` + shell + read) and returns its own best, self-contained draft
   plus its load-bearing claims, assumptions, and "what would change my answer".
2. **Blind.** The coordinator relabels the drafts A/B/C and strips every model
   identity, so neither it nor the judge can favour a particular model's draft
   (the coordinator is itself the "claude" panelist's model).
3. **Judge (compare).** The blinded drafts plus the task go to the `judge`,
   which returns ONE JSON object comparing them across exactly five angles:
   `consensus`, `contradictions`, `partial_coverage`, `unique_insights`,
   `blind_spots`. The judge only compares — it never merges, votes, grades, or
   writes the answer.
4. **Synthesize.** The coordinator reads the judge's five-angle analysis and
   writes ONE final answer from it: builds on the consensus (weighed by the
   evidence each draft supplied), resolves each contradiction by the stronger
   evidence, folds in unique insights worth keeping, and closes the coverage
   gaps and blind spots (or flags any it cannot). The judge owns the
   comparison; the coordinator owns the prose.

## Prerequisites (per machine)
The YAML is portable; the runtime each harness reaches into is not. Each install needs:
- **omnigent** installed.
- **Vendor CLIs + logins:** `claude` (→ Opus 4.8, also runs the judge), `codex`
  (→ GPT-5.5), `pi` (→ GLM 5.2). Install + log in via `omnigent setup` (walks
  per-harness provider/creds). The codex panelist is pinned to the local codex
  CLI subscription (`executor.auth: {type: provider, name: codex}`), so it boots
  on `~/.codex/auth.json` with **no** `$OPENAI_API_KEY`.
- **Model access:** `claude-opus-4-8` (Claude login), `gpt-5.5` (Codex login),
  `z-ai/glm-5.2` (the BARE OpenRouter slug — no `openrouter/` prefix; the pi
  worker passes the model id to OpenRouter verbatim, so a prefix would 404).
  Needs an OpenRouter provider with `$OPENROUTER_API_KEY` **and credits** for
  any paid model — omnigent does not provision credits.
- **The pi 64KB reader patch (PR #48)** — until it merges upstream, see Bootstrap.

**Graceful degradation:** if a leg can't boot (e.g. no OpenRouter credits), the
coordinator proceeds with the remaining experts — the panel still runs on two,
and the judge compares whatever drafts arrived.

## Run
```
omnigent setup          # one-time: provider + login per harness
omnigent run .          # from this directory  (or: omnigent run /path/to/concordia)
```

## Bootstrap: pi 64KB patch (stopgap until PR #48 merges)
The pi leg needs a small additive patch to omnigent's `inner/pi_executor.py`
(chunked stdout reader; removes asyncio's 64KB per-line limit that otherwise
crashes pi on RPC lines >64KB). Until
https://github.com/omnigent-ai/omnigent/pull/48 merges, re-apply it per install
**and after every `uv tool upgrade omnigent`** (upgrades overwrite site-packages).
Intended packaging: an idempotent `bootstrap.sh` (detect marker → no-op if
already patched/merged → back up → apply). Without the patch, keep the pi
panelist tool-light (no >64KB tool outputs).

## Sharing across your machines — two models
- **A) Per-machine clone (simplest):** `git clone`, run the bootstrap, `omnigent run .`.
  Self-contained and version-controlled.
- **B) Shared server (no re-clone):** run one omnigent server you control,
  register once with `omnigent server --agent concordia/`; on each machine
  `omnigent login <server_url>` then `omnigent run --server <url>`, referencing
  it by `agent_id`. Removes the re-clone but **not** the per-machine runtime —
  harnesses run on each laptop, so every machine still needs the CLIs, logins,
  credits, and pi patch above. (No public agent hub exists; the "registry" is
  whatever server you run.)

## Provenance
Pinned Opus-4.8-max coordinator + draft blinding; a separate Fusion judge that
compares the blinded drafts across the five Fusion angles; coordinator-owned
synthesis from that comparison — applied and validated against the omnigent
spec (`omnigent.spec.load` + per-agent `validate`).
