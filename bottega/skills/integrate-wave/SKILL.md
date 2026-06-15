---
name: integrate-wave
description: Load after each wave completes — owned by the coordinator/integrator, not the architect. Dup-scan the wave's worktrees to DETECT cross-slice duplication (routed to the owning slice, never rewritten inline), merge each slice branch into the integration branch one at a time re-greening the gates, and bounce anything beyond a mechanical merge-marker conflict to the owning slice's relevant role-session (its CODER session for an implementation/behavior fix, its REFACTORER session for a cleanup fix).
---

# integrate-wave — assemble one wave onto the integration branch

After a wave's slices finish, the coordinator (acting as integrator) assembles
them onto the integration branch. This is a separation of duties: the integrator
assembles and the architect verifies — the architect does NOT run integration.
The integrator writes NO code: it merges branches, runs gates, and resolves
purely mechanical merge markers, and it routes every fix that needs new or
rewritten code back to the owning slice's relevant role-session — its CODER session
for an implementation/behavior fix, its REFACTORER session for a structure/cleanup
fix.

## 1. Pre-merge duplicate scan — DETECT and ROUTE, never rewrite
Before merging anything, scan ACROSS the wave's worktrees for helpers two slices
introduced independently — `rg` for repeated helper names / signatures / obvious
copy-paste. This scan only DETECTS duplication; you do not consolidate it
yourself. For each real cross-slice duplicate, ROUTE the cleanup to the slice that
should own the shared helper — usually the upstream/producer slice — by continuing
that slice's REFACTORER session (consolidating a shared helper is cleanup, per
run-slice-pipeline's feedback rule) to fold the helper into one home, with the other
slice consuming it; let it re-hand-back, then merge. Never edit, consolidate, or
refactor helpers inline.

## 2. Merge one slice at a time, re-greening after each
For each `slice/*` branch in the wave, in turn:
- Merge it into the integration branch — a git merge, no source authoring.
- Re-run the gates (tests / lint / typecheck, coverage if configured) and confirm
  GREEN before merging the next slice. A red gate after a merge is a stop: if it
  is a purely mechanical merge-marker conflict, resolve the markers (step 3);
  anything else is BOUNCED to the owning slice's relevant role-session (its CODER
  session for an implementation/behavior fix, its REFACTORER session for a cleanup
  fix). Never hand-edit source to force a gate green yourself.

## 3. Conflicts — you resolve only mechanical merge markers
- **Mechanical merge-marker conflicts** — two slices appending to the same list,
  registering adjacent routes, adding sibling entries, where keeping BOTH sides is
  the WHOLE resolution — you may resolve inline: accept both hunks and drop the
  conflict markers. That is conflict resolution, not writing logic.
- **Anything beyond mechanical** — overlapping logic, incompatible shapes, a
  contract that drifted, or any resolution that needs NEW or rewritten code — is
  NOT yours. Bounce it to the OWNING slice's CODER session (reconciling logic is
  implementation work; continue it, per run-slice-pipeline's feedback rule) to
  rebase onto the new integration HEAD and reconcile, then re-merge.

## 4. Advance
When the whole wave is merged and the gates are green, the integration HEAD has
moved. Record the new HEAD in the registry; the NEXT wave branches its worktrees
off this fresh HEAD.
