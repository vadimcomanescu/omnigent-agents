---
name: bootstrap-aps
description: The BOOTSTRAP step the COORDINATOR runs itself (it has shell), ONCE before the first slice wave, from the TARGET repo root. The idempotent verify-then-install procedure that makes the APS toolchain present and pinned — the two SHA-256-verified Go binaries (gherkin-parser + gherkin-mutator) in `.bottega/bin/`, AND a pinned Python 3.12 venv at `.bottega/aps-venv` holding the kit's language package (aps-kit → acceptance-entrypoint-generator + aps-adapter) and the source-mutation tool (mutmut) — records all of it in `.bottega/aps.lock`, and resolves the ABSOLUTE paths threaded into every slice. A NO-OP only when the lock, binaries, venv interpreter, and language package ALL verify.
---

# bootstrap-aps — pin the APS toolchain, verify, record, resolve

The coordinator runs this DIRECTLY at the BOOTSTRAP step (there is no bootstrapper
role). After it runs, the APS tools exist and are pinned, `$TARGET_ROOT/.bottega/aps.lock`
records exactly what landed, and the resolved ABSOLUTE paths are in the registry's
`aps` block for every slice dispatch. It installs the TOOLS only; it never generates
or runs Gherkin against the project (that is the specifier/coder/architect's job per
slice). It is IDEMPOTENT — a re-run with a fully valid lock is a NO-OP — so a resumed
run re-runs it cheaply instead of tracking a separate "already bootstrapped" flag.

## Absolute paths (the env-root invariant, 1.4)
Resolve `TARGET_ROOT` (the target repo absolute path) ONCE at the start and prefix
EVERY target write with it: `$TARGET_ROOT/.bottega/bin`, `$TARGET_ROOT/.bottega/aps-venv`,
`$TARGET_ROOT/.bottega/aps.lock`, and the `$TARGET_ROOT/.gitignore` edit. "Run from the
target root" is NOT sufficient — `sys_os_*` is sandboxed to the launch cwd, so every
shell command here uses `$TARGET_ROOT/...` absolute paths (or `git -C "$TARGET_ROOT"`).
The relative `.bottega/...` forms below are shown for brevity; write them as
`$TARGET_ROOT/.bottega/...`.

## Why a pinned venv (not system pip)
The kit's Python package needs **Python >= 3.10**; a typical system `pip3` is 3.9 and
fails to install it, while an unpinned `uv`/`pipx` run has drifted to 3.14, where
`mutmut` crashes. So the language package and the source-mutation tool go into a venv
pinned to **3.12** — never system pip, never an unpinned interpreter.

## What gets pinned (Python stack)
1. **Two Go binaries** — `gherkin-parser` and `gherkin-mutator` — into
   `<target>/.bottega/bin/`, SHA-256-verified, language-agnostic (used by every
   stack). These come from the kit's `install.sh` (verified prebuilt downloads; no Go
   toolchain needed).
2. **A pinned venv** at `<target>/.bottega/aps-venv` (Python 3.12) holding:
   - **`aps-kit`** (the kit's Python package, tag `v0.1.0`) → the console scripts
     `acceptance-entrypoint-generator` and `aps-adapter`;
   - **`mutmut`** → the source-mutation tool the architect runs.

(TypeScript stack: the binaries are identical; instead of the venv, install the kit's
`typescript/` package and Stryker via the project's npm and record them in the lock's
`toolchain` block in the same shape. The rest of this procedure is written for the
Python path, which the samples exercise.)

## The pinned kit
- `github.com/vadimcomanescu/acceptance-pipeline-kit` at tag **`v0.1.0`** — pinned,
  never `main`, never a floating tag.
- `install.sh` flags: `--version <tag>`, `--bin-dir <dir>`; base URL overridable via
  `APS_DIST_BASE_URL`. It fetches exactly `gherkin-parser` + `gherkin-mutator`,
  checksum-verifies them, and installs them into `--bin-dir`.
- The Python package is installed from the repo subdirectory (no PyPI):
  `git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@v0.1.0#subdirectory=python`.

## The required tool set
The lock is valid only if it RECORDS the FULL required set: both binaries
(`gherkin-parser`, `gherkin-mutator`) AND the venv (interpreter at the pinned version
+ `aps-kit` at its recorded version). A lock missing any required entry is INVALID no
matter how well the entries it does record verify.

## Procedure (idempotent — safe to re-run)

1. **Read the lock.** If `$TARGET_ROOT/.bottega/aps.lock` exists, load it. Absent →
   install (step 6).
2. **Detect the stack** (read-only, under `$TARGET_ROOT`):
   `pyproject.toml`/`setup.py`/`requirements.txt` → **python**;
   `package.json`/`tsconfig.json` → **typescript**.
3. **Verify the binaries.** For EACH of `gherkin-parser`, `gherkin-mutator`: confirm
   the lock has an entry at `.bottega/bin/<tool>`, the binary exists AND is executable
   at `$TARGET_ROOT/.bottega/bin/<tool>`, and its recomputed SHA-256
   (`shasum -a 256 <abs-path>` / `sha256sum <abs-path>`) equals the recorded `sha256`.
   Any absent entry, missing binary, non-executable binary, or mismatch → install.
4. **Verify the venv (full).** All of:
   - the venv interpreter exists at `<lock.venv.interpreter>` AND its version matches
     `lock.venv.python_version` (`"$INTERP" --version` → `Python 3.12.x`);
   - the language package is installed at the recorded version
     (`"$INTERP" -m pip show aps-kit` → `Version:` equals `lock.venv.packages[aps-kit]`);
   - `mutmut` is importable/installed in the venv
     (`"$INTERP" -m pip show mutmut` succeeds);
   - the console scripts resolve (`<venv>/bin/acceptance-entrypoint-generator` and
     `<venv>/bin/aps-adapter` exist and are executable).
   Any failure → install.
5. **NO-OP test.** No-op ONLY when ALL hold: lock present; both binaries recorded,
   present, **executable**, and checksum-matching; the venv interpreter present at the
   pinned version; the language package installed at the recorded version (and `mutmut`
   present); both console-script entrypoints present and **executable**; AND
   `lock.stack` covers the detected stack. When ALL hold → done: report ok and the
   resolved ABSOLUTE paths; touch nothing. If ANY condition fails → do NOT no-op;
   install (step 6). Missing a binary, a checksum, a non-executable binary/entrypoint,
   the venv interpreter at the right version, OR the language package each forces a real
   (re)install — never a no-op.
6. **Install** (every path absolute under `$TARGET_ROOT`).
   - `mkdir -p "$TARGET_ROOT/.bottega/bin"`.
   - Binaries — verified prebuilt download into `$TARGET_ROOT/.bottega/bin/`:
     ```sh
     curl -fsSL https://raw.githubusercontent.com/vadimcomanescu/acceptance-pipeline-kit/v0.1.0/install.sh \
       | sh -s -- --version v0.1.0 --bin-dir "$TARGET_ROOT/.bottega/bin"
     ```
     install.sh checksum-verifies the download and prints `installed <tool> -> <path>`.
   - Pinned venv — create at 3.12 and install the language package + mutmut INTO it
     (never system pip):
     ```sh
     uv venv --python 3.12 "$TARGET_ROOT/.bottega/aps-venv"
     uv pip install --python "$TARGET_ROOT/.bottega/aps-venv/bin/python" \
       "git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@v0.1.0#subdirectory=python"
     uv pip install --python "$TARGET_ROOT/.bottega/aps-venv/bin/python" mutmut
     ```
     (If `uv` is unavailable, the equivalent is
     `python3.12 -m venv "$TARGET_ROOT/.bottega/aps-venv"` then
     `"$TARGET_ROOT/.bottega/aps-venv/bin/python" -m pip install <same two installs>`.)
   - **Verify what landed.** Recompute the SHA-256 of both
     `$TARGET_ROOT/.bottega/bin/*` binaries; read the installed `aps-kit` version
     (`... -m pip show aps-kit`) and the venv's `python --version`. Record exactly what
     you OBSERVE on disk.
7. **Write the lock** (`.bottega/aps.lock`, JSON, written atomically — temp file then
   move). Binary paths are repo-relative (portable, checksummed). The venv is
   machine-local and non-relocatable, so its interpreter/venv/entrypoint paths are
   recorded ABSOLUTE; resume re-verifies them and rebuilds the venv if they no longer
   resolve.
   ```json
   {
     "kit": "github.com/vadimcomanescu/acceptance-pipeline-kit",
     "tag": "v0.1.0",
     "stack": "python",
     "binaries": [
       {"name": "gherkin-parser",  "path": ".bottega/bin/gherkin-parser",  "sha256": "<hex>"},
       {"name": "gherkin-mutator", "path": ".bottega/bin/gherkin-mutator", "sha256": "<hex>"}
     ],
     "venv": {
       "path": "<target-abs>/.bottega/aps-venv",
       "interpreter": "<target-abs>/.bottega/aps-venv/bin/python",
       "python_version": "3.12.x",
       "packages": [
         {"name": "aps-kit", "version": "0.1.0"},
         {"name": "mutmut",  "version": "<observed>"}
       ],
       "entrypoints": {
         "acceptance-entrypoint-generator": "<target-abs>/.bottega/aps-venv/bin/acceptance-entrypoint-generator",
         "aps-adapter": "<target-abs>/.bottega/aps-venv/bin/aps-adapter"
       }
     },
     "bootstrapped_at": "<UTC ISO-8601>"
   }
   ```
8. **gitignore.** Edit `$TARGET_ROOT/.gitignore` to keep `.bottega/aps.lock` TRACKED
   while the binaries, the venv, and the rest of the runtime scratch stay ignored. A
   whole-dir ignore can't re-include a child, so use a contents-ignore with a negation:
   ```gitignore
   .bottega/*
   !.bottega/aps.lock
   ```
   The binaries in `.bottega/bin/` and the venv in `.bottega/aps-venv/` are NEVER
   committed; the lock IS.
9. **Resolve + report, or fail loudly.** Resolve each path the slices need into an
   ABSOLUTE path and write them into the registry `aps` block + the report:
   - `APS_PARSER`  = `<target-abs>/.bottega/bin/gherkin-parser`,
   - `APS_MUTATOR` = `<target-abs>/.bottega/bin/gherkin-mutator`,
   - `APS_VENV`    = the venv path,
   - `APS_GENERATOR` = the `acceptance-entrypoint-generator` entrypoint,
   - `APS_ADAPTER`   = the `aps-adapter` entrypoint.
   The binary paths are repo-relative in the lock, so RESOLVE them against the target
   root before threading — a slice worker cd's into `.bottega/wt/<id>`, where a
   relative path would not resolve. On any failure — download error, checksum
   mismatch, missing binary, venv create/install failure, wrong interpreter version —
   FAIL LOUDLY with the exact command and error, and leave NO half-written lock.

## Idempotency (why a re-run is cheap)
The lock + the on-disk checksums + the venv interpreter version + the installed
package versions ARE the state. A re-run reads the lock, re-verifies all of them,
re-detects the stack, and no-ops only when everything matches. So the coordinator can
re-run BOOTSTRAP on a resumed run without a separate flag; the second run just
confirms and returns the same ABSOLUTE paths. Only a missing binary, a changed
checksum, a missing/wrong-version interpreter, a missing/wrong-version package, or an
uncovered stack triggers a real (re)install.
