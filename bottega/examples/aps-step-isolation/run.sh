#!/usr/bin/env bash
# Regression: two features that SHARE a step text ("a calculator") must collect and
# run together WITHOUT the "duplicate step handler" collision, and acceptance mutation
# must kill every mutant. Proves the per-feature-Registry glue pattern bottega uses.
#
# Requires: uv, curl, network (downloads aps-kit + the gherkin Go binaries, pinned).
#
# All build artifacts (venv, binaries, generated tests) go in an EXTERNAL temp dir so
# this never plants symlinks under the bundle (omnigent's bundle extractor rejects
# links). The committed inputs (features/, sut/, glue/) are read in place.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
KIT_TAG="v0.1.0"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

uv venv --python 3.12 .venv
# aps-kit + mutmut (+ pytest, which mutmut pulls transitively; pinned for reproducibility)
uv pip install --python .venv/bin/python \
  "git+https://github.com/vadimcomanescu/acceptance-pipeline-kit@${KIT_TAG}#subdirectory=python" mutmut pytest
mkdir -p bin
curl -fsSL "https://raw.githubusercontent.com/vadimcomanescu/acceptance-pipeline-kit/${KIT_TAG}/install.sh" \
  | sh -s -- --version "${KIT_TAG}" --bin-dir "${WORK}/bin"

VENV="${WORK}/.venv"
cp -R "${SRC}/sut" sut
for f in subtract multiply; do
  mkdir -p build "generated/${f}"
  "${WORK}/bin/gherkin-parser" "${SRC}/features/${f}.feature" "build/${f}.ir.json"
  APS_FEATURE_PATH="features/${f}.feature" \
    "${VENV}/bin/acceptance-entrypoint-generator" "build/${f}.ir.json" "generated/${f}"
  # the specifier authors this glue INTO the generated dir, per slice
  cp "${SRC}/glue/${f}_conftest.py" "generated/${f}/conftest.py"
done

echo "### gate: both shared-step features collect + run in ONE pytest invocation"
"${VENV}/bin/pytest" generated -q

echo "### acceptance mutation (fresh work-dir + un-stamped feature copy) — expect survived=0"
# gherkin-mutator writes a manifest stamp INTO --feature and caches per --work-dir;
# differential skipping is keyed on both, so mutate a fresh copy with a fresh work-dir.
cp "${SRC}/features/subtract.feature" build/subtract.mut.feature
PATH="${VENV}/bin:${PATH}" "${WORK}/bin/gherkin-mutator" \
  --feature build/subtract.mut.feature --work-dir build/mut \
  --generated-dir generated/subtract --level hard \
  --runner-worker "aps-adapter pytest generated/subtract -q"
echo "OK"
