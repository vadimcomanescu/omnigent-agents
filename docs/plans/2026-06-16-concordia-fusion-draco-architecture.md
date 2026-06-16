# Concordia Fusion and DRACO Architecture Plan

Date: 2026-06-16
Status: draft for implementation handoff
Branch: `research/concordia-fusion-architecture`
Primary files in scope: `concordia/config.yaml`, `concordia/agents/*/config.yaml`, `concordia/README.md`, `README.md`, optional `concordia/evals/draco/*`

## 1. Objective

Upgrade Concordia from "coordinator internally judges then synthesizes" into a clearer Fusion-style team with explicit role separation:

1. A root coordinator/synthesizer receives the user task and never answers from its own unaudited reasoning alone.
2. Three independent panel agents receive the same user task, equivalent tool access, and a shared output contract.
3. A separate judge agent receives blinded A/B/C panel outputs and returns structured JSON to the coordinator.
4. The coordinator writes the final answer from the judge JSON and panel evidence.
5. The existing adversarial verifier remains a separate post-synthesis safety gate for factual, coding, math, version-sensitive, or high-stakes tasks.
6. DRACO is used in two distinct ways:
   - Runtime: optional DRACO-inspired rubric judging, using the DRACO methodology of weighted criteria and MET/UNMET judgments, without using benchmark answer rubrics.
   - Offline evaluation: a separate DRACO benchmark harness may grade Concordia outputs against the real DRACO dataset rubrics, with contamination controls.

The target is not to clone OpenRouter's private Fusion prompt. The target is to implement the public Fusion architecture plus the useful part of DRACO's public judging protocol.

## 2. Source-grounded conclusions from the discussion

### 2.1 What Concordia already gets right

- `concordia/config.yaml` already has a root orchestrator/synthesizer and dispatches to three panel agents: `claude`, `codex`, and `pi`.
- The root prompt already requires parallel fan-out, A/B/C blinding, graceful degradation, evidence-weighted claim handling, synthesis, and a gated verifier.
- The three panel agents already have very similar structured response contracts: answer, load-bearing claims, assumptions, and what would change the answer.
- The existing `verifier` role is useful and should stay. It is not the Fusion judge. It is a later adversarial falsification gate.

### 2.2 What Concordia should change

- The root coordinator currently performs the judge step itself by building the claim table. Fusion's documented shape is different: panel responses go to a separate judge model that returns structured JSON, then the outer model writes the final answer from that JSON.
- The team should add a first-class `judge` agent and make the root call it before final synthesis.
- Panel prompts should keep equivalent deliverable structure and tool budgets. They do not need to be word-for-word identical, but avoid unnecessary identity leakage in the returned payload.
- Tool access should be verified and made symmetric. The current configs give the panel agents `os_env`, which implies local read/shell access in omnigent, but web search and web fetch availability depends on each harness and must be verified instead of assumed.
- The judge should produce machine-readable JSON, not prose. The coordinator is responsible for final prose.

### 2.3 Fusion facts to encode

From the Fusion docs already captured in `docs/research/2026-06-15-openrouter-fusion.md`:

- A task is sent to a panel of models in parallel.
- Panel models have web search and web fetch in the OpenRouter implementation.
- A judge receives all panel responses, compares them, and returns structured JSON.
- Publicly documented judge fields are consensus, contradictions, partial coverage, unique insights, and blind spots.
- The judge compares responses, it does not simply merge them.
- Final-answer ownership depends on the Fusion entry point: in plugin-attached mode, the original model writes the final answer from judge JSON; when `openrouter/fusion` is invoked directly, the judge model writes the final answer from the structured analysis. Concordia intentionally follows the plugin-like coordinator-writes pattern.
- Recursion is capped in OpenRouter Fusion. Concordia should similarly forbid panel and judge agents from re-invoking the whole team.

### 2.4 DRACO facts to encode

From the DRACO dataset and paper, verified during planning from the Hugging Face dataset page and arXiv page but not yet persisted into a local research note:

- DRACO is a benchmark of 100 deep research tasks, not a runtime judge service.
- Each task has a JSON-encoded rubric with weighted criteria across four axes: factual accuracy, breadth and depth of analysis, presentation quality, and citation quality.
- Grading is LLM-as-judge, usually one criterion at a time, returning binary MET/UNMET plus a short justification.
- Positive criteria reward MET. Negative criteria penalize MET.
- Normalized scoring is weighted raw score divided by the sum of positive weights, clamped to 0 to 100 percent.
- The dataset rubrics must not be shown to Concordia's runtime panel or coordinator during benchmark runs.

Implementation guardrail: before implementing WI-005 scoring semantics or WI-006 offline benchmark code, re-fetch the primary DRACO sources and record exact field names, scoring formula, and citation links in either `docs/research/` or `concordia/evals/draco/README.md`. If that verification is not done, mark the DRACO-specific scoring details as unverified and defer WI-006.

## 3. Target architecture

```text
user task
  -> root coordinator/synthesizer
       -> triage task and select judge mode
       -> fan out same task to panel agents in parallel
            -> panel A: independent answer with evidence
            -> panel B: independent answer with evidence
            -> panel C: independent answer with evidence
       -> collect and blind panel outputs as A/B/C
       -> send blinded outputs to judge agent
            -> fusion_compare JSON, always
            -> rubric_grade JSON, when task warrants DRACO-style grading
       -> coordinator writes final answer from judge JSON and evidence
       -> optional verifier falsifies final load-bearing claims
       -> coordinator revises or hedges failed claims
       -> final answer plus bounded panel notes
```

### 3.1 Role definitions

| Role | Agent | Writes final answer? | Sees model identities? | Primary output |
| --- | --- | --- | --- | --- |
| Coordinator/synthesizer | root `concordia/config.yaml` | Yes | Before blinding only | Final user answer and bounded panel notes |
| Panelists | `claude`, `codex`, `pi` | No | Only their own local context | Structured independent answer payload |
| Judge | new `judge` agent | No | No, only A/B/C | Strict JSON analysis and optional rubric grades |
| Verifier | existing `verifier` | No | No need for identities | PASS/FAIL falsification report per claim |
| Offline evaluator | optional eval harness | No | Not applicable | DRACO scores and per-criterion reports |

### 3.2 Judge modes

The judge should support two modes. The coordinator decides which mode to request.

#### Mode A: `fusion_compare`, default for all substantive tasks

The judge receives the user task and blinded panel outputs A/B/C. It returns JSON with:

```json
{
  "status": "ok",
  "mode": "fusion_compare",
  "consensus": [
    {
      "point": "string",
      "supporting_drafts": ["A", "B"],
      "evidence_quality": "strong|medium|weak|none",
      "notes": "string"
    }
  ],
  "contradictions": [
    {
      "issue": "string",
      "draft_positions": {"A": "string", "B": "string", "C": "string"},
      "recommended_resolution": "string",
      "evidence_basis": "string"
    }
  ],
  "partial_coverage": [
    {
      "topic": "string",
      "covered_by": ["A"],
      "missing_from": ["B", "C"],
      "should_include": true
    }
  ],
  "unique_insights": [
    {
      "draft": "A",
      "insight": "string",
      "evidence_quality": "strong|medium|weak|none",
      "carry_forward": true
    }
  ],
  "blind_spots": [
    {
      "gap": "string",
      "importance": "high|medium|low",
      "suggested_handling": "verify|hedge|omit|ask_clarifying_question"
    }
  ],
  "claim_assessments": [
    {
      "claim": "string",
      "supporting_drafts": ["A", "C"],
      "artifact_status": "supports|exists_but_does_not_support|unverified|missing",
      "overstatement": false,
      "verdict": "carry|hedge|verify_first|omit"
    }
  ]
}
```

#### Mode B: `rubric_grade`, selected for deep research or high-stakes tasks

This is DRACO-inspired, not benchmark-rubric leakage. The judge either receives coordinator-proposed criteria or generates a small task-specific rubric from the user task. It then grades drafts or claims per criterion and returns JSON with:

```json
{
  "status": "ok",
  "mode": "rubric_grade",
  "rubric_source": "generated_from_user_task|coordinator_supplied",
  "criteria": [
    {
      "id": "R-001",
      "axis": "factual-accuracy|breadth-and-depth-of-analysis|presentation-quality|citation-quality",
      "weight": 10,
      "requirement": "string",
      "criterion_type": "positive|negative"
    }
  ],
  "draft_grades": {
    "A": [
      {
        "criterion_id": "R-001",
        "verdict": "MET|UNMET",
        "justification": "string"
      }
    ]
  },
  "draft_scores": {
    "A": {"raw_score": 0, "normalized_score": 0.0}
  },
  "synthesis_guidance": {
    "must_include": ["string"],
    "must_avoid": ["string"],
    "needs_verification": ["string"],
    "best_supported_draft_by_axis": {
      "factual-accuracy": "A|B|C|tie|none"
    }
  }
}
```

Rules for `rubric_grade`:

- Use the DRACO grading semantics: MET means the criterion is present in the draft. For negative criteria, MET means the error is present.
- Do not use real DRACO benchmark `answer` rubrics during normal runtime.
- Do not let panelists see any rubric before they answer, unless the user's task explicitly includes their own success criteria.
- Keep rubric size bounded by default, for example 8 to 12 criteria, unless explicitly running an offline benchmark.

### 3.3 Verifier remains separate

The verifier should not replace the judge. Its job is narrower:

- It sees the synthesized draft and load-bearing claims.
- It tries to falsify claims.
- It returns PASS/FAIL with evidence.
- It does not rewrite or improve the answer.

This is stricter than Fusion and should remain a Concordia advantage.

## 4. Implementation work items

### WI-001: Add a dedicated judge agent

Files in scope:

- Create `concordia/agents/judge/config.yaml`.
- Update `concordia/README.md` layout and prerequisites.

Implementation notes:

- Use a different vendor from the coordinator if practical. Recommended first choice: `codex` harness with `gpt-5.5` or another strong non-Claude judge. If that would collide with the verifier, a Gemini/OpenRouter judge is preferable when available.
- The judge prompt must explicitly state that it receives blinded drafts A/B/C and must not infer model identity.
- The judge prompt must forbid final-answer prose. It emits JSON only.
- The judge prompt must support `fusion_compare` and `rubric_grade` modes.
- The judge prompt must distinguish source existence from source support.
- The judge prompt must flag overstated universals and convert them into narrower supported claims.

Acceptance criteria:

- `concordia/agents/judge/config.yaml` exists and parses as YAML.
- The judge's `name` is `judge`.
- The judge has `os_env` access consistent with other agents unless a verified omnigent-supported web-search-only alternative is selected.
- The judge prompt contains explicit JSON-only output requirements.
- The judge prompt contains both mode names: `fusion_compare` and `rubric_grade`.
- The judge prompt forbids writing the final user answer.
- The README lists the judge role separately from the verifier.

Validation refs:

- `python - <<'PY' ... yaml.safe_load(open('concordia/agents/judge/config.yaml')) ... PY`
- `rg -n "fusion_compare|rubric_grade|JSON|final answer|judge" concordia/agents/judge/config.yaml concordia/README.md`

Dependencies: none.

### WI-002: Update the root coordinator to call the judge before synthesis

Files in scope:

- Modify `concordia/config.yaml`.

Implementation notes:

- Add `judge` to `tools.agents`.
- Replace the current internal `JUDGE (claim table)` phase with a phase that sends the blinded A/B/C payloads to `agent="judge"`, `title="concordia-judge"`.
- The root should still own triage, fan-out, collection, blinding, final synthesis, and verifier dispatch.
- The root should not compute the final claim table from scratch before the judge. It may create a compact evidence packet for the judge and then synthesize from judge JSON.
- For high-stakes, factual, coding, math, version-sensitive, deep-research, or citation-heavy tasks, request `rubric_grade` in addition to `fusion_compare`.
- For simple subjective tasks, request only `fusion_compare` or skip the judge only if the task is trivial and the product decision explicitly allows that. Default should be to judge for Concordia's core value proposition.

Acceptance criteria:

- `tools.agents` includes `judge`.
- The root prompt describes judge dispatch after blinding and before synthesis.
- The root prompt says the judge receives blinded A/B/C only.
- The root prompt says the coordinator writes the final answer from judge JSON.
- The root prompt still invokes `verifier` only after synthesis and only when `needs_verification=true`.
- The root prompt preserves graceful degradation if a panelist fails.
- The root prompt defines what to do if the judge fails or returns invalid JSON: fall back to a conservative coordinator synthesis from panel outputs, label judge failure in panel notes, and run verifier when warranted.

Validation refs:

- `rg -n "judge|concordia-judge|fusion_compare|rubric_grade|verifier|needs_verification" concordia/config.yaml`
- YAML parse check for `concordia/config.yaml`.

Dependencies: WI-001.

### WI-003: Standardize panel payload contracts and tool expectations

Files in scope:

- Modify `concordia/agents/claude/config.yaml`.
- Modify `concordia/agents/codex/config.yaml`.
- Modify `concordia/agents/pi/config.yaml`.
- Update `concordia/README.md`.

Implementation notes:

- Keep model-specific `llm` settings and harnesses.
- Make the panel prompt body structurally identical across all three agents.
- Avoid self-identifying model text inside the payload. The description can identify the agent for operators, but the answer should not reveal model/vendor identity.
- Require each panelist to report:
  1. `answer`
  2. `load_bearing_claims`
  3. `evidence_artifacts`
  4. `assumptions`
  5. `what_would_change_my_answer`
  6. `tool_use_summary`
  7. `confidence_boundaries`
- Keep tool output bounded.
- Verify how omnigent exposes web search and web fetch to each harness. If explicit declaration is supported, add it symmetrically. If not supported, document the actual harness behavior and any missing capability.

Acceptance criteria:

- The three panel prompts require the same section names and same required fields.
- No panel prompt instructs the agent to reveal its model/vendor in the returned payload.
- Each panel prompt tells the agent to use available read/bash/web tools when needed and to keep outputs bounded.
- `concordia/README.md` has a "Tool parity" section that states which tools are expected, which are verified, and what remains harness-dependent.
- If web search/fetch cannot be guaranteed by YAML, the README states that limitation plainly instead of implying parity.

Validation refs:

- `rg -n "tool_use_summary|confidence_boundaries|what_would_change|web|search|bash|read" concordia/agents/*/config.yaml concordia/README.md`
- YAML parse checks for all three panel configs.

Dependencies: none.

### WI-004: Define judge JSON schemas and fallback behavior in docs

Files in scope:

- Update `concordia/README.md`.
- Optional create `concordia/schemas/judge_fusion_compare.schema.json`.
- Optional create `concordia/schemas/judge_rubric_grade.schema.json`.

Implementation notes:

- Document the two judge modes and example JSON shapes.
- If schema files are added, keep them small and implementation-facing.
- Define invalid judge output behavior:
  - coordinator tries one bounded repair prompt to the same judge asking for valid JSON only, if the original content is salvageable;
  - if still invalid, coordinator falls back to conservative synthesis and marks `judge_status="failed"` in panel notes.
- Define partial panel behavior:
  - one panel response minimum can proceed;
  - two responses are enough for comparison;
  - missing panelists are recorded as gaps.

Acceptance criteria:

- README explains judge status values: `ok`, `degraded`, `failed`.
- README explains panel status values: `complete`, `partial`, `failed`.
- README explains what happens when judge JSON is invalid.
- If schema files are added, they validate example JSON committed in docs or comments.

Validation refs:

- `rg -n "judge_status|panel_status|degraded|failed|invalid JSON|schema" concordia/README.md concordia/schemas || true`

Dependencies: WI-001, WI-002.

### WI-005: Add DRACO-inspired runtime rubric grading

Files in scope:

- Modify `concordia/agents/judge/config.yaml`.
- Modify `concordia/config.yaml`.
- Update `concordia/README.md`.

Implementation notes:

- The runtime judge may generate a task-specific rubric from the user's task, but it must not retrieve or use DRACO dataset rubrics.
- The rubric should use DRACO's four axes:
  - factual accuracy
  - breadth and depth of analysis
  - presentation quality
  - citation quality
- The rubric should support positive and negative criteria.
- The judge should grade each blinded draft or synthesized candidate with MET/UNMET semantics.
- For runtime latency, default rubric size should be bounded, for example 8 to 12 criteria.
- The root should request rubric grading only when the task warrants it.

Acceptance criteria:

- Judge prompt describes positive and negative criteria exactly enough that negative MET means the draft contains the error.
- Judge prompt includes the four DRACO axes.
- Root prompt describes when to request `rubric_grade`.
- README explicitly states that runtime `rubric_grade` is DRACO-inspired and must not use benchmark answer rubrics.
- README distinguishes runtime rubric mode from offline DRACO benchmark evaluation.

Validation refs:

- `rg -n "factual-accuracy|breadth-and-depth-of-analysis|presentation-quality|citation-quality|positive|negative|MET|UNMET|DRACO-inspired" concordia/agents/judge/config.yaml concordia/config.yaml concordia/README.md`

Dependencies: WI-001, WI-002.

### WI-006: Add an optional offline DRACO evaluation harness

Files in scope:

- Optional create `concordia/evals/draco/README.md`.
- Optional create `concordia/evals/draco/run_sample.py` or equivalent harness script.
- Optional create `concordia/evals/draco/requirements.txt` or use existing project tooling if introduced.

Implementation notes:

- This is separate from runtime Concordia.
- It should ingest the DRACO JSONL dataset only inside the evaluator path.
- It should run Concordia on `problem` without exposing `answer` to panel, judge, coordinator, or verifier.
- It should then grade Concordia's final answer against parsed `answer` rubric using a judge model and DRACO scoring semantics.
- It should support a sample mode first, for example `--limit 1`, before full 100-task runs.
- It should support contamination controls: block Hugging Face DRACO pages, arXiv DRACO page, and any local path containing answer rubrics from panel/judge web fetch/search during benchmark runs when the underlying tools allow domain blocking.

Acceptance criteria:

- A README explains how to run a 1-task smoke evaluation and a full benchmark.
- The harness, if implemented, never passes `answer` into the Concordia runtime call.
- The harness computes raw and normalized scores using DRACO's formula.
- The harness records per-criterion verdicts and justifications.
- The harness documents judge model and temperature/reasoning settings for reproducibility.
- The harness documents contamination controls and any controls that are not technically enforceable in local omnigent.

Validation refs:

- `rg -n "answer|problem|normalized_score|raw_score|MET|UNMET|contamination|blocked" concordia/evals/draco || true`
- If script exists: run one dry parse against a downloaded or fixture JSONL line without invoking paid model calls.

Dependencies: WI-005 is conceptually related but not required.

### WI-007: Update public docs and root README copy

Files in scope:

- Modify `concordia/README.md`.
- Modify root `README.md` Concordia row.
- Optional update `docs/research/2026-06-15-openrouter-fusion.md` with a short addendum if implementation choices supersede older conclusions.

Implementation notes:

- README should describe the new roles: coordinator, panelists, judge, verifier, offline evaluator.
- README should state that the judge returns JSON and the coordinator writes final prose.
- README should state that verifier is not the judge.
- README should state that DRACO is a benchmark plus rubric methodology, not an external runtime service.
- README should avoid claiming exact OpenRouter parity where local omnigent differs.

Acceptance criteria:

- Root README Concordia description mentions explicit judge agent.
- Concordia README layout includes `agents/judge/`.
- Docs distinguish Fusion-style comparison, DRACO-inspired runtime rubric grading, and offline DRACO benchmark evaluation.
- Docs list limitations and open questions.

Validation refs:

- `rg -n "judge|verifier|DRACO|rubric|Fusion|coordinator|synthesizer" README.md concordia/README.md docs/research/2026-06-15-openrouter-fusion.md`

Dependencies: WI-001 through WI-006 as applicable.

### WI-008: Smoke tests and static validation

Files in scope:

- No production config required unless adding scripts under `concordia/evals/draco/`.

Implementation notes:

- Add or document a small validation checklist if no automated harness exists.
- At minimum validate YAML parses and expected terms exist.
- If local model credentials are available, run a cheap smoke prompt through Concordia:
  - subjective prompt, checks judge flow but may skip verifier;
  - factual prompt, checks judge plus verifier flow.
- If credentials are unavailable, record that runtime smoke was not run.

Acceptance criteria:

- All modified YAML files parse.
- Static greps confirm role separation terms exist.
- README has a manual smoke section.
- A developer can run the plan without guessing which commands prove completion.

Validation refs:

```bash
python - <<'PY'
from pathlib import Path
import yaml
for path in Path('concordia').rglob('config.yaml'):
    yaml.safe_load(path.read_text())
    print(path)
PY
rg -n "concordia-judge|fusion_compare|rubric_grade|concordia-verifier" concordia
```

Dependencies: all implementation work items.

## 5. Global acceptance criteria

The implementation is complete when all of the following are true:

1. Concordia has a distinct `judge` agent in `concordia/agents/judge/config.yaml`.
2. The root coordinator dispatches blinded panel outputs to the judge before final synthesis.
3. The judge returns structured JSON only.
4. The coordinator, not the judge, writes the final user answer in normal Concordia mode.
5. The verifier remains a post-synthesis adversarial falsification role, not a replacement for the judge.
6. Panel agents have equivalent output contracts and documented tool expectations.
7. Tool parity is either implemented or explicitly documented as harness-dependent.
8. Runtime DRACO-inspired rubric grading is clearly separated from offline DRACO benchmark grading.
9. Offline DRACO benchmark docs or harness, if implemented, prevent rubric leakage into the Concordia runtime path.
10. README files match the implemented architecture.
11. YAML parse validation passes for every `config.yaml` under `concordia/`.
12. At least one smoke path is documented, and if credentials are available, executed.

## 6. Suggested implementation order

0. Re-verify DRACO primary sources before coding DRACO-specific scoring or benchmark harness details.
1. WI-001, add judge agent.
2. WI-002, route root coordinator through judge.
3. WI-003, standardize panel contract and document tool parity.
4. WI-004, document/schema judge JSON and fallback behavior.
5. WI-005, add DRACO-inspired runtime rubric mode.
6. WI-007, update docs.
7. WI-008, validate.
8. WI-006, add offline DRACO harness only after the runtime architecture is stable.

WI-006 is deliberately last because benchmark infrastructure can distract from the core architecture. The runtime role separation should land first.

## 7. Non-goals

- Do not attempt to recover OpenRouter's private judge prompt.
- Do not expose DRACO benchmark answer rubrics to runtime panelists, coordinator, judge, or verifier.
- Do not remove the verifier just because a judge exists.
- Do not make all three panelists the same model or same vendor.
- Do not claim exact Fusion parity unless web_search, web_fetch, bash, recursion bounds, and judge behavior have all been verified locally.
- Do not add long-running full DRACO benchmark runs as default tests.

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Web search/fetch parity is not declarable in omnigent YAML | Panel runs are less Fusion-like than docs claim | Verify harness support first, document exact behavior, avoid false README claims |
| Judge JSON is malformed | Coordinator cannot reliably synthesize from it | Add one repair attempt and a conservative fallback path |
| DRACO-style rubric mode becomes too expensive | Latency and cost increase | Bound runtime criteria count, reserve full per-criterion grading for offline evals |
| Judge and verifier roles blur | Prompts become inconsistent and hard to debug | Keep judge comparative/rubric JSON only, verifier PASS/FAIL falsification only |
| Panel identity leaks into judge context | Blinding loses value | Remove model identity from returned panel payloads and make root strip identities |
| Benchmark contamination | DRACO scores become meaningless | Keep `answer` rubrics evaluator-only and block known DRACO pages where possible |

## 9. Open questions for the developer

1. Does omnigent support explicit web search or web fetch tool declarations in this agent YAML format, or are those harness-specific?
2. Which non-Claude model should be the judge to maximize vendor independence while preserving JSON reliability?
3. Should `rubric_grade` evaluate each draft separately, the coordinator's first synthesis candidate, or both?
4. Should judge calls be one combined call for `fusion_compare` plus `rubric_grade`, or two calls for simpler failure isolation?
5. Is an offline DRACO harness in this repo desired now, or should it be a follow-up after Concordia v2 ships?

Recommended defaults:

- Use one judge call for `fusion_compare` on every substantive task.
- Use either a second judge call or a separate mode request for `rubric_grade` only on high-stakes and deep-research tasks.
- Keep the offline DRACO harness as a follow-up unless the immediate goal is benchmark evidence.

## 10. Subagent review result

A fresh `reviewer` subagent evaluated this plan against current Concordia files and `docs/research/2026-06-15-openrouter-fusion.md`, using DRACO-inspired axes: factual accuracy, breadth/depth, presentation quality, and grounding quality.

Result: good enough to hand off, no blockers.

Important fixes from the reviewer were applied:

- Clarified Fusion final-answer ownership by entry point: plugin-attached Fusion returns judge JSON to the original model, direct `openrouter/fusion` has the judge model write from the structured analysis, and Concordia intentionally follows the plugin-like coordinator-writes pattern.
- Added a DRACO source re-verification guardrail before implementing DRACO-specific scoring or offline benchmark code.

## 11. DRACO-style self-evaluation of this plan

This section applies a small DRACO-inspired rubric to the plan itself. It is not a DRACO benchmark score.

| Criterion | Axis | Weight | Verdict | Justification |
| --- | --- | ---: | --- | --- |
| Separates Fusion runtime roles into panel, judge, coordinator, and verifier | factual-accuracy | 10 | MET | The architecture and work items define all four roles distinctly. |
| Distinguishes DRACO benchmark rubrics from runtime DRACO-inspired judging | factual-accuracy | 10 | MET | Sections 2.4, 3.2, WI-005, and WI-006 keep these separate. |
| Gives implementation-ready file paths | breadth-and-depth-of-analysis | 8 | MET | Each work item lists files in scope and validation refs. |
| Provides bounded acceptance criteria | presentation-quality | 8 | MET | Work items and global acceptance criteria are explicit and checkable. |
| Claims verified web-search parity in current Concordia without proof | factual-accuracy | -10 | UNMET | The plan explicitly avoids that claim and requires verification. |
| Hides open decisions from developer | presentation-quality | -5 | UNMET | Open questions are listed in section 9. |
| Provides citations or source anchors to project evidence | citation-quality | 5 | MET | The plan cites repo files and the existing research doc; it avoids unsupported external claims beyond prior fetched docs. |

Normalized score under this small rubric: 100 percent, because all positive criteria are met and no negative criteria are triggered. This score is a planning sanity check, not an external benchmark result.
