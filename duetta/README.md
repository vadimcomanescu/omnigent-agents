# Duetta, two-voice brainstorming for omnigent

**Duetta** is a self-contained omnigent team for getting two independent model
perspectives on the same question. It sends every substantive prompt to a
Claude responder and a GPT responder, then presents the two answers side by
side with a short agreement/difference summary.

This is the local customized variant of Omnigent's bundled Debby example. The
important change is the GPT voice: it uses the local `codex` harness, pinned to
`gpt-5.5`, instead of the OpenAI Agents SDK harness. That keeps the upstream
example clean while letting this copy run through the Codex CLI's own
`codex login` auth path.

## Layout

```
duetta/
├── config.yaml          # coordinator, Claude SDK harness
├── agents/
│   ├── claude/          # Claude brainstorming responder
│   └── gpt/             # GPT responder through local Codex CLI
└── skills/
    └── debate/          # optional cross-critique loop
```

## Prerequisites

- `omnigent` installed.
- Claude configured through `omnigent setup`, a Claude subscription login, or
  `ANTHROPIC_API_KEY`.
- Codex CLI logged in with `codex login`.

The GPT responder does not require `OPENAI_API_KEY`; it runs through the Codex
CLI login.

## Run

```bash
omnigent run duetta/
```

From inside this directory:

```bash
omnigent run .
```

Ask for debate, critique, stress-testing, or use `/debate` to load the debate
skill and have the two voices critique each other before Duetta synthesizes.
