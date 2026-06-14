# Panel — mixture-of-experts agent for omnigent

A local "Fusion-style" mixture-of-experts orchestrator. One task fans out in
parallel to three model-pinned experts, then a fixed **Opus 4.8 @ max**
synthesizer blinds the drafts (A/B/C), builds an evidence-weighted claim table
(flagging "unverified consensus"), and — on factual/coding/high-stakes tasks —
runs a different-vendor verifier before answering.

## Layout
```
panel/
├── config.yaml            # orchestrator + synthesizer: Opus 4.8 @ max, cost advisor OFF
└── agents/
    ├── claude/            # expert — Claude Opus 4.8 @ max
    ├── codex/             # expert — GPT-5.5 @ xhigh
    ├── pi/                # expert — DeepSeek-V4-Pro via OpenRouter
    └── verifier/          # gated adversarial verifier — GPT-5.5 (≠ synthesizer vendor)
```

## Prerequisites (per machine)
The YAML is portable; the runtime each harness reaches into is not. Each install needs:
- **omnigent** installed.
- **Vendor CLIs + logins:** `claude` (→ Opus 4.8), `codex` (→ GPT-5.5), `pi` (→ DeepSeek).
  Install + log in via `omnigent setup` (walks per-harness provider/creds).
- **Model access:** `claude-opus-4-8` (Claude login), `gpt-5.5` (Codex login),
  `openrouter/deepseek/deepseek-v4-pro` (an OpenRouter provider with
  `$OPENROUTER_API_KEY` **and credits** — DeepSeek-V4-Pro is paid; omnigent does
  not provision credits).
- **The pi 64KB reader patch (PR #48)** — until it merges upstream, see Bootstrap.

**Graceful degradation:** if a leg can't boot (e.g. no OpenRouter credits), the
orchestrator proceeds with the remaining experts — the panel still runs on two.

## Run
```
omnigent setup          # one-time: provider + login per harness
omnigent run .          # from this directory  (or: omnigent run /path/to/panel)
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
  register once with `omnigent server --agent panel/`; on each machine
  `omnigent login <server_url>` then `omnigent run --server <url>`, referencing
  it by `agent_id`. Removes the re-clone but **not** the per-machine runtime —
  harnesses run on each laptop, so every machine still needs the CLIs, logins,
  credits, and pi patch above. (No public agent hub exists; the "registry" is
  whatever server you run.)

## Provenance
P0 (pinned Opus-4.8-max synthesizer + draft blinding), P1 (evidence-based claim
table + unverified-consensus rule), P2 (gated different-vendor verifier) —
applied and cross-reviewed against the omnigent spec.
