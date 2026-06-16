# Polly Agentic-Code-Review Improvements Plan

Date: 2026-06-16
Status: draft for implementation handoff
Branch: `research/polly-agentic-review-improvements`
Source article: Addy Osmani, "Agentic Code Review" (https://addyosmani.com/blog/agentic-code-review/)
Primary files in scope: a new owned `polly/` team in this repo (`polly/config.yaml`, `polly/agents/*/config.yaml`, `polly/skills/cross-review/SKILL.md`, `polly/skills/fanout/SKILL.md`, `polly/skills/investigate/SKILL.md`, `polly/README.md`), plus the root `README.md` team table. Explicitly NOT in scope: the upstream `examples/polly` directory in the `omnigent-ai/omnigent` repo.

## 1. Objective

Encode the useful, evidence-backed lessons of Addy Osmani's "Agentic Code Review" into polly's review discipline, while respecting where polly's source of truth actually lives.

Two things must be true at the end:

1. Polly's review process scales its rigor to each task's blast radius, captures the implementer's reasoning instead of discarding it, specifically guards the test/CI diff against tampering, and hands the human a risk verdict instead of borrowed confidence.
2. These changes land in a polly variant that **Vadim owns** inside this repo (`omnigent-agents`), NOT as in-place edits to the upstream `examples/polly` reference, which Vadim tracks read-only and cannot push to.

The target is not to bolt an enterprise review pipeline onto every task. The target is a depth dial that spends extra rigor only where blast radius justifies it, plus three cheap, always-on hygiene wins (evidence packet, test-diff guard, risk verdict).

## 2. Source-grounded conclusions from the discussion

### 2.1 What polly already gets right (validated by the article)

These are not changes. They are existing polly invariants the article independently argues for, recorded so no work item accidentally regresses them.

- **Cross-vendor review independence.** The article's empirical core: across 146 real PRs and 617 flagged locations, 93.4% of issues were caught by exactly one of four AI reviewers, ~6% by two, almost none by three, zero by all four. Heterogeneous reviewers find nearly disjoint bug sets; correlated blind spots are worst *within* a model family. Polly's hard rule, that review is always a different vendor than the implementer (Claude's diff to Codex or Pi, never back to Claude), is exactly what this data rewards. Keep it.
- **Human owns the merge.** The article's hardest line: "a model cannot be paged at 3am." Polly never merges; the implementer opens the PR and the human merges. Keep it.
- **Reviewer is a sensor, not a verdict.** Polly's reviewer reports findings and never edits; only the implementer's PR ships, so a reviewer's stray edits cannot reach the deliverable. Keep it.
- **Deterministic gates owned by the orchestrator.** The article calls deterministic gates "the one part of the pipeline that cannot be talked out of its verdict by a confident paragraph." Polly runs test/lint/typecheck gates itself rather than trusting a worker's "looks green." Keep it.

### 2.2 What the article says to add (the gaps), ranked by leverage

1. **Risk-tiering by blast radius (highest leverage).** The article's entire "what to do" section is tiered: a config tweak earns a linter and a glance; an auth or payments path earns types, tests, two different reviewers, and a security pass. Polly today applies one uniform process (implement, one cross-review, done) to a README-adjacent helper and a database migration alike. Without a tier dial, every other improvement below would add friction to trivial diffs, which is the exact failure mode the article warns against. This is the prerequisite for everything else.
2. **Two reviewers for high-blast-radius diffs.** Direct consequence of the 93.4%-disjoint finding: for load-bearing changes, one reviewer is not enough. The experiment paired reviewers of deliberately different character (everyday-correctness vs production-severity) and caught a set neither found alone. Polly has three workers and can afford implementer + two distinct-vendor reviewers on high-tier tasks (e.g. Codex implements; Claude_code + Pi review).
3. **Implementer evidence packet (capture reasoning before it's discarded).** The article's sharpest insight: the agent does reason, but that reasoning is thrown away at diff-time, so the reviewer becomes "the first human to ever lay eyes on this code." Polly gives the reviewer the diff plus polly's contract, but not the implementer's "here is what I tried and ruled out." Requiring every implementer to write intent + alternatives-ruled-out + evidence into the PR body, and feeding that to the reviewer, is the lever against the measured review-time blowup and is cheap because the reasoning already existed.
4. **Test-diff / CI-tampering guard.** Named agent failure mode: change behavior, then "fix" the test by rewriting the assertion to match the now-broken behavior; or weaken CI to reach green (remove tests, skip lint, lower coverage thresholds), "not maliciously, just gradient descent finding the cheapest path to green." A green check over 200 edited tests means nothing. Polly's gate step checks pass/fail but does not flag tampering.
5. **Human risk verdict at closeout (anti borrowed-confidence).** When the loop says "looks good" with no human understanding in it, "the system's certainty becomes yours and nobody understood anything." Today polly marks a passed PR ready with a URL, which invites a rubber stamp. Closeout should hand the human a short risk verdict: what is load-bearing, what the reviewers disagreed on, and crucially what was out of scope / never checked. That last item is the article's "behavior nobody specified" gap: a requirement no one wrote down is a *shared* blind spot of implementer and reviewer alike (they both work from polly's contract), so only the human can close it.
6. **Plan/contract quality (front-load the thinking).** The article cites a practitioner shipping ~40 PRs/day largely unattended by investing in detailed plans: "plan quality determines how long they can run unattended." Polly's tech-lead decomposition is that step; a richer acceptance contract half-solves the missing-intent problem before any code exists. Cheap and entirely within the orchestrator role.

### 2.3 The ownership/topology constraint (why this repo, not `examples/polly`)

This is the decisive non-negotiable that shapes every work item below.

- The canonical polly lives in the upstream `omnigent-ai/omnigent` repo at `examples/polly`. In Vadim's checkout of that repo, `upstream` is `omnigent-ai/omnigent` with push DISABLED, every commit touching `examples/polly` is by upstream authors, and upstream actively edits those files.
- Therefore, editing `examples/polly/skills/*/SKILL.md` in place would cause recurring merge conflicts on every `git fetch upstream && rebase`, and would be a divergent, unreviewed local fork (the duplicate-surface rot that the "no shadow canon" principle in the operator's global agent doctrine exists to prevent).
- The clean path is to **fork polly into a directory Vadim owns**. This repo (`omnigent-agents`, origin `github.com/vadimcomanescu/omnigent-agents`) is exactly that place: it is a library of self-contained omnigent teams (`duetta`, `concordia`, `bottega`), each launched with `omnigent run <dir>/`. A new `polly/` team here is fully Vadim's to iterate; upstream `examples/polly` stays pristine and merges clean.
- Repo constraint that matters for the fork: per this repo's README, "omnigent has no cross-directory include/import, so teams are independent by design, shared pieces are copied, not linked." So forking polly means **copying** the canonical polly (config + agents + skills) into `polly/`, then editing the copy. There is no symlink/include shortcut.
- An opinionated slice that proves out here can later be offered upstream as a PR (the only conflict-free way to change canon). That is a follow-up, not part of this plan.

### 2.4 Honest caveats about the evidence

- The strongest effect sizes in the article (Faros, CodeRabbit) come from vendors selling into this market, and Addy says so himself. Act on the *direction* of the findings, not on any single percentage as load-bearing.
- The 93.4%-disjoint finding is the most decision-relevant number and comes from an independent practitioner experiment, so the two-reviewer recommendation rests on firmer ground than the vendor latency/throughput figures.
- One mechanic is currently **unverified**: exactly how a forked polly variant in this repo references its own skills directory (does `polly/config.yaml` point at `polly/skills/`, or is there a different wiring?). This must be confirmed by investigation before the fork is wired (see WI-000). Until then, treat the `polly/skills/` paths in this plan as the intended layout, not a verified one.

## 3. Target architecture

```text
human goal
  -> polly orchestrator (tech lead)
       -> [NEW] triage: classify task blast-radius tier (trivial | standard | high)
       -> [STRENGTHENED] write acceptance contract scaled to tier
       -> per task: spin worktree + implementer sub-agent
            -> implementer drives to green, opens its own PR
            -> [NEW] PR body MUST include evidence packet:
                 intent, alternatives ruled out, evidence/gates run
       -> polly runs deterministic gates itself (existing)
       -> [NEW] polly diffs test/CI config for tampering BEFORE review
       -> cross-review, depth scaled by tier:
            trivial  -> gates + orchestrator glance, optional single review
            standard -> one different-vendor reviewer (today's default)
            high     -> two distinct-vendor reviewers + explicit security/perf pass
            (reviewer always gets diff + contract + evidence packet; never the worktree)
       -> blocking issues become fix-tasks; loop until clean
       -> [NEW] closeout: hand human a RISK VERDICT, not just "passed":
            load-bearing surface, reviewer disagreements, out-of-scope / never-checked
       -> human merges (unchanged)
```

### 3.1 Where each change lives

| Change | Surface | Skill / file |
| --- | --- | --- |
| Blast-radius triage + tier definitions | orchestrator persona | `polly/agents/<polly>/config.yaml` (system prompt) |
| Tier-scaled acceptance contract | orchestrator persona | `polly/agents/<polly>/config.yaml`; cross-refs `decomposition` discipline |
| Depth dial (per-tier review intensity) | review skill | `polly/skills/cross-review/SKILL.md` |
| Two-reviewer path for high tier | review skill | `polly/skills/cross-review/SKILL.md` |
| Test-diff / CI-tampering guard | review skill | `polly/skills/cross-review/SKILL.md` |
| Human risk verdict at closeout | review skill | `polly/skills/cross-review/SKILL.md` |
| Implementer evidence packet requirement | fan-out skill + implement contract | `polly/skills/fanout/SKILL.md` |
| Investigation depth note (optional, light) | investigate skill | `polly/skills/investigate/SKILL.md` |

### 3.2 Blast-radius tiers (proposed default rubric)

The triage step assigns exactly one tier per task. The classifier is the orchestrator, at decomposition time, recorded in the task contract.

| Tier | Examples | Review depth | Extra gates |
| --- | --- | --- | --- |
| `trivial` | docs, comments, copy, isolated test-only helper, dependency-free string change | gates + orchestrator glance; single review optional | none |
| `standard` | typical feature code, refactor within one module, bug fix with tests | one different-vendor reviewer (current default) | full test/lint/typecheck |
| `high` | auth, payments, authz, data migrations, deletion/destructive ops, concurrency, public API contracts, anything touching secrets or money | two distinct-vendor reviewers + explicit security/perf pass | full gates + test-diff guard escalated to "read tests first" |

Tier assignment is conservative: when in doubt, round up. The orchestrator must state the chosen tier and the one-line reason in the contract, so the human can override at the plan gate.

### 3.3 Evidence packet (implementer -> PR body -> reviewer)

Every implementer PR body must include a bounded section:

```
## Evidence packet
- Intent: what this change is supposed to do, in one or two sentences.
- Approach: the chosen approach in brief.
- Alternatives ruled out: options considered and why rejected (>=1 if any non-trivial choice was made).
- Evidence: gates/tests run and their results; key files touched and why.
- Risks / unknowns: anything the implementer is unsure about or left out of scope.
```

Polly passes this packet to the reviewer alongside the diff and contract. The reviewer is told to use it as the implementer's stated reasoning, not as ground truth (it is a claim to check, not a guarantee).

### 3.4 Risk verdict (closeout -> human)

When a PR passes cross-review, polly does not just post "passed + URL." It posts a short verdict:

```
## Risk verdict
- Tier: trivial | standard | high (+ one-line reason)
- Load-bearing surface: what in this diff actually carries risk if wrong.
- Reviewer agreement: clean | reviewers disagreed on X (with resolution).
- Out of scope / never checked: requirements or behaviors not covered by the contract,
  so neither implementer nor reviewer evaluated them; the human must judge these.
- Recommendation: ready to merge / merge after human checks the out-of-scope items.
```

## 4. Work items

### WI-000: Verify polly fork wiring before any copy (guardrail)

Type: investigation only. No file changes.

Implementation notes:

- Dispatch a read-only explore sub-agent against the upstream omnigent repo / `examples/polly` to answer, with file/line citations:
  1. How does a polly agent config reference its skills directory? Is it `examples/polly/skills/`, a path in `config.yaml`, or harness-discovered?
  2. What is the minimal set of files/dirs that constitute a launchable polly team (`config.yaml`, `agents/`, `skills/`, anything else)?
  3. Does `omnigent run <dir>/` resolve skills relative to the team dir, so a copied `polly/` here would load `polly/skills/` and not the upstream copy?
  4. Confirm the canonical skill files in scope: `cross-review`, `fanout`, `investigate` SKILL.md, and the orchestrator system prompt location.
- Record findings in `docs/research/2026-06-16-polly-fork-wiring.md` before WI-001.

Acceptance criteria:

- A research note exists stating, with citations, exactly how a copied polly team in this repo resolves its own skills and persona.
- If the wiring is NOT a simple per-dir copy, this plan's `polly/skills/` paths are corrected in WI-001 before any copy happens.

Dependencies: none. Blocks WI-001.

### WI-001: Fork canonical polly into an owned `polly/` team

Files in scope:

- Create `polly/` (copy of canonical polly: `config.yaml`, `agents/`, `skills/`, per WI-000 findings).
- Update root `README.md` team table and layout with a `polly` row.

Implementation notes:

- Copy, do not link (no cross-dir include in omnigent).
- The first commit of `polly/` should be a faithful copy of canonical polly with NO behavior changes, so the diff for WI-002+ is purely the improvements. Record the upstream commit SHA the copy was taken from, in `polly/README.md`, for future re-sync.
- Add a short `polly/README.md` describing this as Vadim's iterating fork of canonical polly, the upstream source SHA, and the intent to upstream proven slices later.

Acceptance criteria:

- `polly/` launches as a team (or, if no credentials, YAML parses and structure matches a canonical polly team per WI-000).
- `polly/README.md` records the upstream source SHA and the fork rationale.
- Root `README.md` lists `polly` in the team table and layout.
- The WI-001 commit contains no behavior changes versus canonical polly.

Dependencies: WI-000.

### WI-002: Add blast-radius triage + tier rubric to the orchestrator persona

Files in scope:

- Modify the polly orchestrator system prompt (`polly/agents/<polly>/config.yaml` per WI-000).

Implementation notes:

- Add a triage step to decomposition: every task gets exactly one tier (`trivial` | `standard` | `high`) using the section 3.2 rubric, recorded in the task contract with a one-line reason.
- "When in doubt, round up." High-tier triggers are enumerated (auth, payments, authz, migrations, destructive ops, concurrency, public API, secrets/money).
- The tier is stated to the human at the plan gate so they can override.

Acceptance criteria:

- Orchestrator prompt defines the three tiers and their triggers.
- Orchestrator prompt requires recording tier + reason in each task contract.
- Orchestrator prompt instructs surfacing the tier to the human at the plan gate.

Validation refs:

- `rg -n "blast.radius|tier|trivial|standard|high|round up" polly/agents/*/config.yaml`

Dependencies: WI-001.

### WI-003: Scale review depth by tier in `cross-review` (incl. two-reviewer path)

Files in scope:

- Modify `polly/skills/cross-review/SKILL.md`.

Implementation notes:

- Add a "depth dial" keyed to the task tier from WI-002.
- `trivial`: gates + orchestrator glance; single different-vendor review optional.
- `standard`: one different-vendor reviewer (preserve today's behavior exactly).
- `high`: two **distinct-vendor** reviewers (e.g. implementer Codex -> reviewers Claude_code + Pi) plus an explicit security/perf pass; ground this in the 93.4%-disjoint finding.
- Keep the existing invariants: reviewer gets diff + contract only, never the worktree; reviewer reports, never edits; loop on blocking issues.
- State the two-available-vendor precondition: a high-tier task needs at least two non-implementer vendors available from the roster preflight; if not, polly cannot run the high-tier review and must pull in the human at the plan gate (mirrors polly's existing cross-vendor-availability rule).

Acceptance criteria:

- The skill maps each tier to a concrete review intensity.
- `standard` behavior is unchanged from today.
- `high` requires two distinct-vendor reviewers and names the availability precondition + escalation when it can't be met.
- All existing cross-review invariants (diff+contract only, no edits, loop) remain stated.

Validation refs:

- `rg -n "tier|two reviewers|distinct.vendor|security pass|depth" polly/skills/cross-review/SKILL.md`

Dependencies: WI-002.

### WI-004: Add the test-diff / CI-tampering guard to `cross-review`

Files in scope:

- Modify `polly/skills/cross-review/SKILL.md`.

Implementation notes:

- Before declaring gates green, polly inspects the diff for tampering signals: deleted/skipped tests, assertions rewritten to match new behavior, lowered coverage thresholds, disabled lint rules, weakened CI config, `xfail`/`skip`/`only` markers added.
- For `high` tier, instruct the reviewer to read the test diff FIRST, before the implementation diff.
- A green gate over a modified test suite is explicitly stated to be insufficient on its own; the test-diff must be accounted for in the risk verdict.
- This is a hygiene check that runs on `standard` and `high`; on `trivial` it is a quick scan.

Acceptance criteria:

- The skill enumerates concrete tampering signals to scan for.
- The skill tells the reviewer to read test changes first on high-tier tasks.
- The skill states that a passing gate over an edited test suite is not sufficient evidence by itself.

Validation refs:

- `rg -n "tamper|test diff|coverage threshold|skip|xfail|read tests first|weaken" polly/skills/cross-review/SKILL.md`

Dependencies: WI-001 (lands cleanly after WI-003 but is independent of it).

### WI-005: Require the implementer evidence packet in `fanout` + implement contract

Files in scope:

- Modify `polly/skills/fanout/SKILL.md`.
- Reflect the requirement wherever the implement-task contract is described (orchestrator persona if that is where the implement dispatch contract lives, per WI-000).

Implementation notes:

- Every implementer PR body must include the section 3.3 evidence packet (intent, approach, alternatives ruled out, evidence, risks/unknowns).
- Polly passes the evidence packet to the reviewer alongside diff + contract.
- Reviewer is told to treat the packet as the implementer's stated reasoning, a claim to check, not ground truth.
- Keep it bounded so it does not balloon PR bodies; a few lines per field.

Acceptance criteria:

- `fanout` requires the evidence packet in every implementer PR body and defines its fields.
- The review hand-off (in `fanout` and/or `cross-review`) includes passing the packet to the reviewer.
- The reviewer instruction frames the packet as claims to verify, not guarantees.

Validation refs:

- `rg -n "evidence packet|alternatives ruled out|intent|risks / unknowns|stated reasoning" polly/skills/fanout/SKILL.md polly/skills/cross-review/SKILL.md`

Dependencies: WI-001.

### WI-006: Add the human risk verdict at closeout to `cross-review`

Files in scope:

- Modify `polly/skills/cross-review/SKILL.md`.

Implementation notes:

- When a PR passes review, polly posts the section 3.4 risk verdict instead of just "passed + URL."
- The "out of scope / never checked" line is mandatory and is the anti-borrowed-confidence mechanism: it names requirements/behaviors the contract did not cover, which neither implementer nor reviewer evaluated, so the human must.
- Verdict must name reviewer disagreements and their resolution when two reviewers ran (high tier).

Acceptance criteria:

- The skill defines the risk-verdict format with the mandatory "out of scope / never checked" line.
- The skill requires reporting reviewer disagreement (when more than one reviewer ran).
- The skill keeps "the human merges" unchanged and frames the verdict as decision support, not a merge approval.

Validation refs:

- `rg -n "risk verdict|out of scope|never checked|load-bearing|borrowed confidence|reviewer agreement" polly/skills/cross-review/SKILL.md`

Dependencies: WI-003 (verdict references tier and two-reviewer disagreement).

### WI-007: Strengthen acceptance-contract authoring in the orchestrator persona

Files in scope:

- Modify the polly orchestrator system prompt (`polly/agents/<polly>/config.yaml`).

Implementation notes:

- Make the acceptance contract richer and scaled to tier: explicit done-criteria, the load-bearing behaviors, and an explicit "out of scope" list (which feeds the risk verdict's never-checked line).
- Cross-reference the existing `decomposition` / `zero-context-planning` discipline rather than re-deriving it; the point is that plan quality determines unattended run length.
- A `high`-tier contract must enumerate the security/perf concerns the reviewers will be told to check.

Acceptance criteria:

- The orchestrator prompt requires an explicit out-of-scope list in each contract.
- The contract requirements scale with tier (high tier enumerates security/perf concerns).
- The prompt references the planning discipline skill(s) rather than duplicating them.

Validation refs:

- `rg -n "acceptance contract|out of scope|load-bearing|done criteria|plan quality" polly/agents/*/config.yaml`

Dependencies: WI-002.

### WI-008: Update READMEs and register the polly team

Files in scope:

- Modify root `README.md` (team table + layout, if not fully done in WI-001).
- Finalize `polly/README.md` with the new review discipline summary.

Implementation notes:

- `polly/README.md` should summarize the four behavioral upgrades (tiering, evidence packet, test-diff guard, risk verdict) and the two-reviewer high-tier path, and state plainly that this is a Vadim-owned fork that may be upstreamed slice by slice.
- Avoid claiming parity with canonical polly where this fork deliberately differs.

Acceptance criteria:

- Root README lists `polly` with an accurate one-line description.
- `polly/README.md` documents the upgrades and the fork/upstream intent.
- READMEs match the implemented skill/persona changes.

Validation refs:

- `rg -n "polly|tier|evidence packet|risk verdict|two reviewers" README.md polly/README.md`

Dependencies: WI-002 through WI-007 as applicable.

### WI-009: Validate the behavior change before declaring done

Files in scope:

- No production files required; optional notes under `docs/research/`.

Implementation notes:

- These are persona/coordinator behavior changes, so validate with the `validating-agent-improvements` approach (playground A/B simulation of polly behavior on representative tasks: one trivial, one standard, one high-tier auth/payments-shaped task).
- Static validation at minimum: every modified `config.yaml` parses; greps confirm the new terms exist in persona and skills.
- A/B target: the high-tier task should trigger two reviewers, the evidence packet, the test-diff guard, and a risk verdict; the trivial task should NOT spin up the heavy path (guarding against added friction on cheap diffs, the article's named anti-pattern).
- If credentials are unavailable, record that runtime A/B was not run and rely on static checks plus a documented manual walk-through.

Acceptance criteria:

- All modified YAML parses.
- Static greps confirm tiering, evidence packet, test-diff guard, and risk-verdict terms exist.
- An A/B or documented walk-through shows the high-tier path activates the heavy review and the trivial path does not.

Validation refs:

```bash
python - <<'PY'
from pathlib import Path
import yaml
for path in Path('polly').rglob('config.yaml'):
    yaml.safe_load(path.read_text())
    print(path)
PY
rg -n "tier|evidence packet|risk verdict|tamper|two reviewers|out of scope" polly
```

Dependencies: all implementation work items.

## 5. Global acceptance criteria

The implementation is complete when all of the following are true:

1. A Vadim-owned `polly/` team exists in this repo, copied from canonical polly with the upstream source SHA recorded; `examples/polly` upstream is untouched.
2. The orchestrator persona classifies every task into a blast-radius tier and records tier + reason in the contract.
3. `cross-review` scales review depth by tier, with `standard` unchanged and `high` requiring two distinct-vendor reviewers plus a security/perf pass.
4. `cross-review` includes a test-diff / CI-tampering guard.
5. `cross-review` ends with a human risk verdict that always names what was out of scope / never checked.
6. `fanout` requires an evidence packet in every implementer PR body, and polly passes it to the reviewer as claims to verify.
7. The acceptance contract is richer and tier-scaled, with an explicit out-of-scope list.
8. All existing polly invariants are preserved: cross-vendor review, implementer-only PRs, reviewer never edits, deterministic gates owned by polly, human merges.
9. READMEs match the implemented behavior; no false parity claims.
10. Every `config.yaml` under `polly/` parses; static greps confirm the new behavior terms.
11. The behavior change is validated (A/B simulation or documented walk-through) showing heavy review on high tier and no added friction on trivial tier.

## 6. Suggested implementation order

0. WI-000: verify fork wiring (investigation) before any copy.
1. WI-001: fork canonical polly into `polly/` as a faithful, behavior-neutral copy.
2. WI-002: add blast-radius triage + tier rubric (the dial everything else keys off).
3. WI-003: scale review depth by tier + two-reviewer high path.
4. WI-005: implementer evidence packet (independent; can land alongside WI-003).
5. WI-004: test-diff / CI-tampering guard.
6. WI-006: human risk verdict at closeout.
7. WI-007: strengthen acceptance-contract authoring.
8. WI-008: update READMEs.
9. WI-009: validate the behavior change.

Tiering (WI-002) is deliberately first among the behavior changes: every other improvement is something to *spend* only on higher-blast-radius work, so without the dial they would add friction to trivial diffs, the exact failure the article warns against.

## 7. Non-goals

- Do NOT edit upstream `examples/polly` in place; that is the merge-conflict + shadow-canon trap this plan exists to avoid.
- Do NOT remove or weaken any existing polly invariant (cross-vendor review, implementer-only PRs, reviewer-never-edits, human-merges, orchestrator-owned gates).
- Do NOT make polly merge PRs or auto-approve; the risk verdict is decision support, never a merge.
- Do NOT apply the heavy high-tier path to trivial diffs; the whole point of tiering is to avoid that friction.
- Do NOT treat any single vendor-sourced percentage from the article as load-bearing; act on direction.
- Do NOT upstream these changes to `omnigent-ai/omnigent` as part of this plan; that is a later, separate PR for proven slices only.
- Do NOT have polly self-mutate its own running config to "patch itself"; these changes affect future polly launches from `polly/`, not the live session.

## 8. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Fork wiring assumed wrong (skills not resolved per-dir) | Forked polly silently loads upstream skills; changes have no effect | WI-000 verifies the wiring with citations before any copy |
| Tier classifier is too coarse or gameable | Heavy review on cheap work, or cheap review on risky work | Conservative "round up" default; tier + reason stated to human at plan gate for override |
| Two-reviewer high path can't run (fewer than two non-implementer vendors available) | High-tier task cannot get independent double review | WI-003 states the availability precondition and escalates to the human instead of faking it |
| Evidence packet balloons PR bodies or becomes box-ticking | Noise, reviewer ignores it | Bounded fields; reviewer told to treat it as claims to verify, not ground truth |
| Risk verdict becomes a rubber-stamp template | Borrowed confidence returns under a new name | "Out of scope / never checked" line is mandatory and human-facing; verdict explicitly not a merge approval |
| Fork drifts from canonical polly over time | Re-sync with upstream gets harder | Record upstream source SHA in `polly/README.md`; upstream proven slices to shrink the delta |
| Acting on vendor-inflated numbers | Over-engineering the pipeline | Treat percentages as directional; the firmest finding (disjoint reviewers) is the independent one |

## 9. Open questions for the developer

1. WI-000's core unknown: does a copied `polly/` team resolve `polly/skills/` per-dir, or is there another wiring (config path, harness discovery)? This blocks the copy.
2. Tier boundaries: is the three-tier rubric (trivial/standard/high) right, or is a fourth tier (e.g. `critical` for irreversible/destructive ops with a mandatory human pre-merge walk-through) worth adding?
3. Two-reviewer pairing on high tier: fixed roles (e.g. always Claude_code + Pi review Codex) or chosen per task by which vendors are available and which model fits?
4. Should the test-diff guard run as a deterministic polly-owned script (greps for skip/xfail/coverage-threshold deltas) in addition to the reviewer instruction, so it cannot be talked out of its verdict?
5. Is a polly fork wanted as a standing team in this repo now, or should the changes first be prototyped as a throwaway overlay and only promoted once validated?

Recommended defaults:

- Start with the three-tier rubric; add `critical` only if real destructive-op tasks show up.
- Choose the two high-tier reviewers per task from available vendors rather than fixing roles, to stay robust to roster gaps.
- Implement the test-diff guard as BOTH a deterministic polly-owned scan and a reviewer instruction; determinism is the article's "cannot be argued out of its verdict" principle.
- Stand `polly/` up as a real owned team now (the whole point is that Vadim owns the iteration surface), but keep WI-001 behavior-neutral so the upgrade diff is clean and reversible.

## 10. Provenance and corrections

This plan supersedes two earlier assertions made during the originating discussion:

- That these skill edits were "skills I own" and should land directly in canonical `examples/polly`. That was wrong: `examples/polly` is upstream (`omnigent-ai/omnigent`), push-disabled and actively edited upstream. Editing it in place causes recurring merge conflicts and shadow canon. The corrected target is an owned fork in this repo.
- That "a local copy = shadow canon" is a single written rule. It is an extrapolation from two real sources: the binding skill-location rule in polly's own system instructions, and the general "no shadow canon" principle in the operator's global agent doctrine. The extrapolation is defensible but is not a single cited sentence; recorded here so the plan does not overstate its receipts.

The decisive reason this plan targets `omnigent-agents/polly/` and not `examples/polly`: the git remotes show Vadim tracks `examples/polly` read-only and upstream actively edits it, so any in-place change is a recurring conflict. The condition that would flip this: if Vadim actually owned `examples/polly` as his source of truth, which the remotes show he does not.
