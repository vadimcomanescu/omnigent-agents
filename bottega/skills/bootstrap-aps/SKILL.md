---
name: bootstrap-aps
description: Load when the coordinator dispatches the bootstrapper ONCE before the first slice wave. The idempotent verify-then-install procedure, run from the TARGET repo root, that makes the pinned APS toolchain (gherkin-parser + gherkin-mutator) present and SHA-256-verified in `<target>/.bottega/bin/`, records them in `.bottega/aps.lock`, and reports their resolved ABSOLUTE paths — a NO-OP when the lock is already valid.
---

# bootstrap-aps — make the APS toolchain present, verified, and recorded

Run from the TARGET repo root (not a slice worktree). The goal is narrow: after
this runs, `gherkin-parser` and `gherkin-mutator` exist in `<target>/.bottega/bin/`,
their SHA-256 digests are recorded in `<target>/.bottega/aps.lock`, and the resolved
ABSOLUTE paths are handed back. The procedure is IDEMPOTENT — it verifies before it
installs, so a re-run with a valid lock is a NO-OP. It installs the TOOLS only; it
never generates or runs Gherkin against the project (a deliberate follow-on).

## The pinned kit
- `github.com/vadimcomanescu/acceptance-pipeline-kit` at tag **`v0.1.0`** (pinned —
  never `main`, never a floating tag).
- Its `install.sh` detects OS/arch, downloads the prebuilt `gherkin-parser` and
  `gherkin-mutator` from the GitHub Release, **checksum-verifies** them, and installs
  them into `--bin-dir` (default `$HOME/.local/bin`). Flags: `--version <tag>`,
  `--bin-dir <dir>`. The base URL is overridable via `APS_DIST_BASE_URL`. No Go
  toolchain is needed — the binaries arrive as verified downloads.
- Per-language packages live under `python/`, `typescript/`, `go/`, `rust/` in a
  clone of the kit at the tag.

## Procedure (idempotent — safe to re-run)
1. **Read the lock.** If `.bottega/aps.lock` exists, load it. Absent lock -> go
   straight to install (step 5).
2. **Verify each recorded tool.** For every entry in `tools[]`, confirm the binary
   exists at its recorded path AND recompute its SHA-256 (`shasum -a 256 <path>` or
   `sha256sum <path>`) and confirm it equals the recorded `sha256`. A missing binary
   or a mismatch invalidates the lock.
3. **Detect the stack.** Inspect the target root (read-only):
   - `pyproject.toml` / `setup.py` / `requirements.txt` -> **python**
   - `package.json` / `tsconfig.json` -> **typescript**
   - `go.mod` -> **go**
   - `Cargo.toml` -> **rust**
4. **NO-OP test.** If the lock is present, EVERY recorded binary exists with a
   matching checksum, AND the lock's `stack` equals the detected stack -> you are
   done. Report ok and the resolved ABSOLUTE paths; touch nothing (no fetch, no
   re-write of the lock).
5. **Otherwise BOOTSTRAP.**
   - Ensure `.bottega/bin/` exists (`mkdir -p .bottega/bin`).
   - Fetch the pinned kit at `v0.1.0` and install the binaries into `.bottega/bin/`,
     e.g.:
     ```sh
     # binaries — SHA-256-verified prebuilt download, into the target's .bottega/bin
     curl -fsSL https://raw.githubusercontent.com/vadimcomanescu/acceptance-pipeline-kit/v0.1.0/install.sh \
       | sh -s -- --version v0.1.0 --bin-dir "$(pwd)/.bottega/bin"
     ```
     (or clone the kit at the tag and run `./install.sh --version v0.1.0 --bin-dir
     <target>/.bottega/bin`). install.sh checksum-verifies the download and prints
     `installed <tool> -> <path>` for each binary.
   - **Verify what landed.** Recompute the SHA-256 of `.bottega/bin/gherkin-parser`
     and `.bottega/bin/gherkin-mutator` and keep the digests — install.sh already
     verified the download, but you record the digest you OBSERVE on disk.
   - **Per-language package.** Clone the kit at the tag and install the package for
     the DETECTED stack from its `python/` / `typescript/` / `go/` / `rust/` tree as
     that stack needs (e.g. the language adapter/generator the slices will call).
     Install only the detected stack's package, not all four.
6. **Write the lock.** Write/update `.bottega/aps.lock` (JSON) with paths
   repo-relative as `.bottega/bin/<tool>`:
   ```json
   {
     "kit": "github.com/vadimcomanescu/acceptance-pipeline-kit",
     "tag": "v0.1.0",
     "stack": "python|typescript|go|rust",
     "tools": [
       {"name": "gherkin-parser",  "path": ".bottega/bin/gherkin-parser",  "sha256": "<hex>"},
       {"name": "gherkin-mutator", "path": ".bottega/bin/gherkin-mutator", "sha256": "<hex>"}
     ],
     "bootstrapped_at": "<UTC ISO-8601, e.g. 2026-06-16T12:00:00Z>"
   }
   ```
   Write it atomically (write a temp file, then move it into place) so a crash never
   leaves a half-written lock.
7. **gitignore.** Ensure the target repo keeps `.bottega/aps.lock` TRACKED while the
   binaries and the rest of the runtime scratch stay ignored. Because a whole-dir
   ignore (`.bottega/`) cannot re-include a child, use a contents ignore with a
   negation so the committed lock survives:
   ```gitignore
   .bottega/*
   !.bottega/aps.lock
   ```
   The binaries in `.bottega/bin/` are NEVER committed; the lock IS.
8. **Report or fail loudly.** On success, report STATUS ok and the resolved ABSOLUTE
   paths (`<target>/.bottega/bin/gherkin-parser`, `<target>/.bottega/bin/gherkin-mutator`).
   On any failure — download error, checksum mismatch, missing binary — FAIL LOUDLY
   with the exact command and error, and leave NO half-written lock behind.

## Idempotency (why a re-run is cheap)
The lock + on-disk checksums ARE the state. A re-run reads the lock, re-verifies the
binaries, re-detects the stack, and — if all match and the stack is covered —
no-ops. So the coordinator can re-dispatch the bootstrapper on a resumed run without
tracking a separate "already bootstrapped" flag; the second run just confirms and
returns the same paths. Only a missing binary, a changed checksum, or a stack the
lock doesn't cover triggers a real (re)install.

## Handoff
Hand back to the coordinator as structured text:
- **STATUS:** ok | failed;
- the resolved ABSOLUTE tool paths — `APS_PARSER=<abs>` and `APS_MUTATOR=<abs>` —
  which the coordinator threads into every slice dispatch packet;
- the lock contents you wrote or validated (kit, tag, stack, each tool's sha256);
- **what you did:** NO-OP (lock already valid) or INSTALLED (which tools + the
  per-language package for which stack);
- on **failure:** the exact command + error, and confirmation no partial lock was
  written.
Never write feature code, never run Gherkin features or mutation against the
project, never open or merge a PR.
