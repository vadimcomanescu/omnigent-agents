---
name: integrate-wave
description: Load after each wave completes — owned by the coordinator/integrator, not the architect. Accept ONLY slices in ready_to_integrate; dup-scan the wave's worktrees to DETECT cross-slice duplication (routed to the owning slice, never rewritten inline), merge each accepted slice branch into the integration branch one at a time re-greening the gates, and bounce anything beyond a mechanical merge-marker conflict to the owning slice's relevant role-session (its CODER session for an implementation/behavior fix, its REFACTORER session for a cleanup fix).
---

# integrate-wave — assemble one wave onto the integration branch

After a wave's slices finish, the coordinator (acting as integrator) assembles them
onto the integration branch. Separation of duties: the integrator ASSEMBLES, the
architect VERIFIES — the architect does NOT run integration. The integrator writes NO
code: it merges branches, runs gates, resolves purely mechanical merge markers, and
routes every fix that needs new or rewritten code back to the owning slice's relevant
role-session.

## 0. Accept ONLY `ready_to_integrate` (the integrate gate)
Per registry-state, a slice is eligible to merge ONLY in phase `ready_to_integrate`
(refactorer handback present AND gates green at its `green_head`). REJECT anything
else and route it to the role that owns its next step — never merge it:
- `spec_done` (only the specifier's RED acceptance is committed) → its CODER session;
- `coder_green` (green but not yet cleaned) → its REFACTORER session;
- a running phase, or a stale `ready_to_integrate` whose gates are NOT actually green
  at `green_head` → re-verify / re-dispatch, do not merge.
A red-only or unverified branch is never treated as a finished slice.

## 1. Pre-merge duplicate scan — DETECT and ROUTE, never rewrite
Before merging anything, scan ACROSS the wave's worktrees for helpers two slices
introduced independently — `rg` for repeated helper names / signatures / obvious
copy-paste. This scan only DETECTS. For each real cross-slice duplicate, ROUTE the
cleanup to the slice that should own the shared helper — usually the upstream/producer
slice — by continuing that slice's REFACTORER session (consolidating a shared helper
is cleanup) to fold the helper into one home, the other slice consuming it; let it
re-hand-back, then merge. When several duplicates route at once, dispatch them in
parallel via **fanout**. Never edit, consolidate, or refactor helpers inline.

## 2. Merge one slice at a time, re-greening after each
For each accepted `ready_to_integrate` `slice/*` branch, in turn:
- Merge it into the integration branch — a git merge, no source authoring.
- Re-run the gates (tests / lint / typecheck, coverage if configured) and confirm
  GREEN before merging the next slice. A red gate after a merge is a stop: a purely
  mechanical merge-marker conflict you resolve (step 3); anything else is BOUNCED to
  the owning slice's relevant role-session (CODER for behavior/implementation,
  REFACTORER for cleanup). Never hand-edit source to force a gate green.
- Mark each merged slice `integrated` (or `contract_landed` for a spine stub, per
  registry-state) and PERSIST.

## 3. Conflicts — you resolve only mechanical merge markers
- **Mechanical merge-marker conflicts** — two slices appending to the same list,
  registering adjacent routes, adding sibling entries, where keeping BOTH sides is the
  WHOLE resolution — you may resolve inline: accept both hunks, drop the markers. That
  is conflict resolution, not writing logic.
- **Anything beyond mechanical** — overlapping logic, incompatible shapes, a contract
  that drifted, or any resolution needing NEW or rewritten code — is NOT yours. Bounce
  it to the OWNING slice's CODER session to rebase onto the new integration HEAD and
  reconcile, then re-merge.

## 4. Advance
When the whole wave is merged and the gates are green, the integration HEAD has moved.
Record the new HEAD in the registry and PERSIST; the NEXT wave branches its worktrees
off this fresh HEAD.
