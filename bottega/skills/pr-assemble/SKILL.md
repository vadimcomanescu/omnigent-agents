---
name: pr-assemble
description: Load ONCE after architect sign-off — the coordinator opens the team's single PR for the integration branch and STOPS. The one home for the final-PR mechanics and the human-merge rule. No worker runs this; the coordinator opens exactly one PR for the whole feature and never merges.
---

# pr-assemble — open the one PR, then stop

After architect-verify SIGNS OFF, the whole feature sits on the integration branch
`bottega/<slug>` at a green HEAD. The coordinator opens ONE PR and the run ends. This
is the team's only end state.

## Preconditions (all true before you open the PR)
- architect-verify returned SIGN-OFF — not a bounce, and not mid bounce-loop.
- Every slice is `integrated`/`done` (the DAG drained) and no `contract_landed` spine
  has an unfinished implementation follow-up (see registry-state).
- The full gate suite is green at the current `integration_head`. RE-RUN the gates
  yourself at that HEAD — do not infer green from a worker handback.

## Open exactly one PR
First PUSH the integration branch to set an upstream (the PR step needs a remote
branch), then open the PR. `gh` has NO `-C` flag (that's git) — run `gh` from the
target root via `cd`, or pass the repo with `gh -R <owner>/<repo>`:
```sh
git -C "$TARGET_ROOT" push -u origin bottega/<slug>
cd "$TARGET_ROOT" && gh pr create --base <base-branch> --head bottega/<slug> \
   --title "<feature>" --body "<summary>"
# or, without cd: gh -R <owner>/<repo> pr create --base <base-branch> --head bottega/<slug> ...
```
The body summarizes the feature and the slices, and records the verification
evidence the architect produced — the green gate suite, the source-mutation result
(survivors killed), the cross-slice DRY result, and the APS acceptance-mutation
result (`gherkin-mutator` survived=0/errors=0). Open it ONCE for the whole feature —
never a PR per slice or per wave.

## Then stop — a human merges
The coordinator NEVER merges and never enables auto-merge. Pushing the integration
branch and opening the one PR are the only writes to a remote the team makes. Report
the PR URL and END the run.
