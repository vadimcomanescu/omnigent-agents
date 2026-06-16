#!/usr/bin/env bash
# Demonstrates the EQUIVALENT-MUTANT classification gate. A validation feature
# (type-only "rejects non-numeric" + divide-by-zero) yields acceptance mutants that
# CANNOT change the scenario outcome and so survive even though the handlers correctly
# read operand values from the IR (not hardcoded). The architect must classify each
# survivor as KILLABLE (=> BOUNCE) or EQUIVALENT (=> sign-off with a justification).
#
# Expected: total=4 killed=1 survived=3 errors=0, where all 3 survivors are equivalent
# and the 1 killed (the divisor cell) proves the gate still catches load-bearing cells.
# See equivalent-mutants.json for the recorded classification.
#
# Requires: uv, curl, network. Builds in an EXTERNAL temp dir (no symlinks under the bundle).
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
KIT_TAG="v0.1.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python \
  "git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@${KIT_TAG}#subdirectory=python" mutmut pytest
mkdir -p bin
curl -fsSL "https://raw.githubusercontent.com/vadimcomanescu/acceptance-pipeline-kit/${KIT_TAG}/install.sh" \
  | sh -s -- --version "${KIT_TAG}" --bin-dir "${WORK}/bin"

VENV="${WORK}/.venv"
cp -R "${SRC}/sut" sut
mkdir -p build generated
"${WORK}/bin/gherkin-parser" "${SRC}/features/validation.feature" build/validation.ir.json
APS_FEATURE_PATH="features/validation.feature" \
  "${VENV}/bin/acceptance-entrypoint-generator" build/validation.ir.json generated
cp "${SRC}/glue/validation_conftest.py" generated/conftest.py

echo "### baseline: validation scenarios pass"
"${VENV}/bin/pytest" generated -q

echo "### acceptance mutation — expect total=4 killed=1 survived=3 (3 equivalent, 1 killed)"
# runner-worker uses the VENV pytest explicitly (BUG B): no PATH surgery, aps_kit importable.
cp "${SRC}/features/validation.feature" build/validation.mut.feature
set +e
"${WORK}/bin/gherkin-mutator" \
  --feature build/validation.mut.feature --work-dir build/wd \
  --generated-dir generated --level hard \
  --runner-worker "${VENV}/bin/aps-adapter ${VENV}/bin/pytest generated -q" 2>&1 | tee mut.out
rc="${PIPESTATUS[0]}"
set -e

echo "### exit code: $rc (1 is expected — survivors present; the architect classifies them)"
grep -E "^total=|^survived|^killed" mut.out
killed="$(grep -cE '^killed' mut.out || true)"
survived="$(grep -cE '^survived' mut.out || true)"
[ "$killed" -ge 1 ]   || { echo "FAIL: expected >=1 killed (gate must still bite)"; exit 1; }
[ "$survived" -ge 1 ] || { echo "FAIL: expected equivalent survivors to demonstrate the gate"; exit 1; }
echo "OK — $killed killed, $survived survived (classified in equivalent-mutants.json)"
