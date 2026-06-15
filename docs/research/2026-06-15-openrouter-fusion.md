# OpenRouter Fusion: how it works, the judge, and how it compares to Claude deep research

- **Date:** 2026-06-15
- **Question:** How does OpenRouter Fusion ("Fusion beats Frontier") work, and is it the same thing as Claude deep research / the multi-agent workflow we run, but multi-model? Follow-ups: what is it for, how does the judge work, can we see the judge prompt, is OpenRouter open source.
- **Primary source:** <https://openrouter.ai/blog/announcements/fusion-beats-frontier>
- **Method:** deep-research workflow (Scope -> Search -> Fetch -> 3-vote adversarial Verify -> Synthesize), 64 agents, ~1.29M tokens. Anthropic **Sonnet** for web search/fetch legwork, Anthropic **Opus** for reasoning (scope, verification, synthesis). Judge mechanics and open-source status confirmed by direct doc/GitHub fetches afterward.
- **Verification:** 16 falsifiable claims fact-checked, 11 survived the 2-of-3 adversarial refute gate, 5 refuted. Refuted items are flagged inline below.

---

## 1. How OpenRouter Fusion works

Fusion is a multi-model deliberation mechanism exposed as a single API call. A prompt is dispatched to a **panel of models running in parallel**, each with web search and web fetch enabled, then all responses go to a separate **judge model** that produces a structured analysis, from which a final answer is written. [1][3][4][5][6]

Mechanism, precisely:

- **Panel size is 1 to 8 models.** [4][5] Default panel is three models from different vendors; per the provider's model page the defaults are Claude Opus, GPT-latest, and Gemini Pro-latest [5], i.e. a deliberately **cross-vendor** mix.
- **Each panelist answers independently and in parallel**, with `openrouter:web_search` and `openrouter:web_fetch` available. [1][3][6] The web search tool defaults to max 8 tool calls, configurable 1 to 16. [4]
- **A judge model reads every panel response** and emits structured JSON: consensus, contradictions, partial coverage, unique insights, blind spots. The final answer is derived from that analysis. [4][6] (Judge detail in section 5.)
- **Recursion is hard-capped at one level.** Panel and judge models cannot invoke Fusion again; the plugin refuses to inject the tool a second time, enforced via an `x-openrouter-fusion-depth` header. [4][5]

What "Fusion beats Frontier" means: the vendor claim is that a *panel* deliberated over by a judge can outscore any *single* frontier model on a deep-research benchmark. [1]

> Refuted in verification: the strong characterizations that the judge "compares but does not merge" (pure arbitration) **and** that it "combines their answers into a final response" (blending) were each refuted as standalone claims (3/3 votes against each) at synthesis time. The direct doc fetch in section 5 resolves this: the judge **compares without merging** and a final answer is then **written from** that structured comparison.

## 2. Benchmark and performance claims

All numbers below are **vendor-reported** (OpenRouter's own announcement/docs), not independently reproduced. The underlying benchmark, **DRACO** (cross-domain Deep Research Accuracy, Completeness, Objectivity), is a real separately published artifact [8][9], but the Fusion scores on it come from the vendor.

Verified (quote-to-source fidelity held; not independent reproduction):

- On DRACO (100 deep-research tasks), a **budget panel (Gemini 3 Flash, Kimi K2.6, DeepSeek V4 Pro) beat GPT-5.5 and Opus 4.8**, within 1% of Fable 5's score at 50% of the cost. [1][2]

Cost / latency (verified faithful to source, vendor-reported):

- Default 3-model panel: **~4-5x the cost** of a single completion, scaling **linearly with panel size**. [3]
- Priced as the **sum of the underlying model completions**, not one model call. [6]
- **Latency ~2-3x** a standard single-model call. [1]

Refuted / do not present as fact:

- The pairwise figures "Fable 5 + GPT-5.5 fused = 69.0% vs 65.3% solo" and "Opus 4.8 self-fused = 65.5%, +6.7 over 58.8% solo" did **not** survive (2/3 and 3/3 refuting). Unconfirmed.
- A Hacker News gloss of the Budget/Quality presets also failed (2/3 refuting). [7] The directionally similar *budget-panel* claim above is the one that held, sourced to OpenRouter itself.

Bottom line: architecture and cost/latency multipliers are well-documented; headline benchmark wins are vendor-reported and the most quotable individual numbers did not survive quote-checking. Treat "Fusion beats Frontier" as a vendor claim, not a settled result.

## 3. Fusion vs Claude Research vs this workflow

| Axis | OpenRouter Fusion | Claude Research | This deep-research workflow |
|---|---|---|---|
| Multi-agent orchestration | Panel of 1-8 models + 1 judge, one deliberation round, recursion capped at one level [4][5] | Lead/orchestrator decomposes the query, spawns parallel subagents, then synthesizes | Deterministic orchestrator over fixed phases (Scope -> Search -> Fetch -> Verify -> Synthesize) |
| Web-search fan-out | Every panelist has web search + fetch, default 8 / max 16 calls [1][3][4] | Subagents each search and return findings | Parallel web searches, then Fetch retrieves sources |
| Verification / fact-check | Implicit only: judge surfaces consensus, contradictions, blind spots [4][6]; no independent refutation step | No dedicated adversarial stage; lead agent synthesizes | Explicit, adversarial: 3-vote fact-check per claim, 2/3 refutes kills it |
| Vendor / model heterogeneity | **Cross-vendor**: default Claude Opus + GPT-latest + Gemini Pro-latest [5] | **Single-vendor**: all Claude subagents | **Single-vendor, multi-tier**: Sonnet legwork + Opus reasoning |

**Alike:** all three are orchestrator-plus-parallel-workers designs that fan out web searches then synthesize one cited answer.

**Fundamental differences:**

- **Vendor diversity is the defining axis.** Fusion's whole thesis is putting *different companies'* frontier models on the same prompt so their independent strengths and errors get cross-checked. Claude Research and this workflow are multi-*agent within a single vendor*; this run is heterogeneous only by Anthropic model tier (Sonnet vs Opus). "Multi-model" in the original question really means multi-*vendor*.
- **Synthesis primitive.** Fusion's distinctive move is a dedicated judge doing one structured consensus/contradiction/blind-spot pass. Claude Research's lead agent synthesizes its own subagents. This workflow separates synthesis from an explicit verification gate that can kill claims by majority vote, a discrete step neither of the others documents.

## 4. Bottom line on the comparison

**Yes, same family, with one important correction.** Fusion is a multi-agent, parallel-search, synthesize-with-a-judge system in the same broad family as Claude Research and this workflow. But "Claude deep research but multi-model" understates Fusion's one defining axis: it is multi-*vendor* (Claude + GPT + Gemini against the same prompt, judged across them), whereas the others are multi-*agent within one vendor*. That cross-vendor diversity is what its "beats frontier" claim rests on.

### When to use Fusion

- **Use it for:** one-off high-stakes questions where being wrong is expensive and cross-vendor cross-checking catches a single model's blind spot or hallucination (deep research/due diligence, high-consequence single answers, or when you don't know which model is best and want to hedge in one call).
- **Don't use it for:** high-volume, real-time, or cost-sensitive workloads (4-5x cost, 2-3x latency); tasks where you already know the best model; agentic tool-loops (capped at one recursion level, cost compounds).
- **Relative to our own workflows (deep-research, concordia):** ours already do "many minds + reconcile" and add an explicit adversarial kill-the-claim vote that Fusion's single judge pass lacks. Fusion's added value is cross-vendor robustness with zero orchestration code behind one API call. Flip toward Fusion as a default if single-vendor runs turn out confidently wrong in ways a GPT or Gemini panelist would have caught.

## 5. How the judge works (direct doc fetch)

- **What it gets:** all panel responses, plus its own `openrouter:web_search` / `openrouter:web_fetch` access, capped by `max_tool_calls` (default 8, range 1-16). [4]
- **What it does: compare, not merge.** The docs are explicit that it **"doesn't merge them"**; it performs comparative analysis and returns structured JSON with five fields:
  - **Consensus** - points all/most models agree on, treated as higher-confidence
  - **Contradictions** - where models disagree
  - **Partial coverage** - topics treated incompletely
  - **Unique insights** - contributions from individual models
  - **Blind spots** - gaps none addressed
- **Who writes the final answer (two modes, documented slightly differently):**
  - *Plugin attached to your own model:* the judge returns the JSON, and **your original model** writes the final answer from it. [4]
  - *`openrouter/fusion` invoked directly:* the **judge model itself** writes the final answer from the structured analysis. [6]
  - Either way the answer is **written from the structured comparison**, not emitted as a raw merge. This reconciles the two claims that were refuted at synthesis: neither pure selection nor text-blend, but "analyze structurally, then synthesize a fresh answer informed by that analysis."
- **Which model is the judge:** default is the first model in the Quality preset, **Claude Opus Latest**; configurable via the `model` field. If you attach the plugin to your own model, the judge defaults to that same model. [4][5]

Config knobs:

| Field | Controls | Default |
|---|---|---|
| `analysis_models` | the panel (models that answer) | Quality preset panel |
| `model` | the judge | Claude Opus Latest (or your model if plugin-attached) |
| `max_tool_calls` | judge's web search/fetch budget | 8 (range 1-16) |

## 6. Can we see the judge's actual prompt? No.

OpenRouter does **not** publish the judge's system prompt. The docs expose the judge's *behavior* and *output schema* (the five-field JSON), and the configurable knobs (`model`, `analysis_models`, `max_tool_calls`), but there is no parameter to view or override the judge's instruction text, and no source repo contains it. The prompt runs server-side and is internal.

The only way to obtain the text is **empirical reconstruction**: invoke `openrouter/fusion` (or the plugin) and probe the judge to emit its own instructions, triangulating across runs. Caveat: that is a best-effort approximation (models paraphrase/hallucinate their own system prompts, and OpenRouter may sanitize/refuse), not ground truth. Not yet attempted.

## 7. Is OpenRouter open source? No (only the SDKs).

The **platform is proprietary**. The [OpenRouterTeam GitHub org](https://github.com/OpenRouterTeam) contains only client-side artifacts:

| Repo | What it is | License |
|---|---|---|
| `typescript-sdk`, `python-sdk`, `go-sdk` | client SDKs | Apache-2.0 |
| `ai-sdk-provider` | Vercel AI SDK provider | Apache-2.0 |
| `typescript-agent` | Agent SDK | - |
| `openrouter-examples` | integration examples | MIT |
| `skills`, `docs`, `awesome-openrouter` | skills, docs, app list | - |

No backend, router logic, or Fusion/judge implementation is published. The "OpenRouter is open" impression comes from (1) the open-source SDKs, (2) it being a gateway to many open-weight models, and (3) recurring confusion (see the HN thread literally titled "isn't OpenRouter already open source?" [10]). The self-hostable open-source analog people point to is LiteLLM. Consequence: the judge prompt cannot be read from source because the source is not published.

## Sources

1. <https://openrouter.ai/blog/announcements/fusion-beats-frontier>
2. <https://openrouter.ai/blog/announcements/fusion-beats-frontier/>
3. <https://openrouter.ai/docs/guides/routing/routers/fusion-router>
4. <https://openrouter.ai/docs/guides/features/plugins/fusion>
5. <https://openrouter.ai/docs/guides/features/server-tools/fusion>
6. <https://openrouter.ai/openrouter/fusion>
7. <https://news.ycombinator.com/item?id=48537641>
8. <https://arxiv.org/abs/2602.11685>
9. <https://huggingface.co/datasets/perplexity-ai/draco>
10. <https://news.ycombinator.com/item?id=44883842>

> Note: sources 7 and 8 (the HN benchmark thread item and the arXiv DRACO id) were surfaced by agents and not independently re-validated end-to-end; the arXiv id in particular should be confirmed before citing DRACO formally.
