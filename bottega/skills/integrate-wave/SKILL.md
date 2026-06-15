---
name: integrate-wave
description: Load after each wave completes — owned by the coordinator/integrator, not the architect. Dup-scan the wave's worktrees, merge each slice branch into the integration branch one at a time re-greening the gates, and bounce non-trivial conflicts to the owning slice's own session.
---

# integrate-wave — assemble one wave onto the integration branch

After a wave's slices finish, the coordinator (acting as integrator) folds them
into the integration branch. This is a separation of duties: the integrator
assembles and the architect verifies — the architect does NOT run integration.

## 1. Pre-merge duplicate scan
Before merging anything, scan ACROSS the wave's worktrees for helpers two slices
introduced independently — `rg` for repeated helper names / signatures / obvious
copy-paste. This is a cheap cross-slice duplication catch BEFORE assembly; fold
obvious duplicates into one home as part of the merge rather than letting both
land.

## 2. Merge one slice at a time, re-greening after each
For each `slice/*` branch in the wave, in turn:
- Merge it into the integration branch.
- Re-run the gates (tests / lint / typecheck, coverage if configured) and confirm
  GREEN before merging the next slice. A red gate after a merge is a stop — fix
  the integration or bounce it (below) before continuing.

## 3. Conflicts
- **Trivial** conflicts — two slices appending to the same list, registering
  adjacent routes, adding sibling entries — resolve inline as part of the merge.
- **Non-trivial** conflicts — overlapping logic, incompatible shapes, a contract
  that drifted — are NOT resolved by the integrator. Bounce the conflict back to
  the OWNING slice's OWN session (continue it, per run-slice-pipeline's
  feedback rule) to rebase onto the new integration HEAD and reconcile, then
  re-merge.

## 4. Advance
When the whole wave is merged and the gates are green, the integration HEAD has
moved. Record the new HEAD in the registry; the NEXT wave branches its worktrees
off this fresh HEAD.
