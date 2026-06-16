# aps-step-isolation — regression: shared step text must not collide

Two features (`features/subtract.feature`, `features/multiply.feature`) **share the
Gherkin step `Given a calculator`**. The kit's `aps_kit.default_registry` is a global
singleton and `Registry.step()` raises `ValueError("duplicate step handler")` on a
duplicate step text; bare `pytest` auto-loads every generated `conftest.py`. So the
naive glue (registering into `default_registry`) makes the **second** feature error
the whole gate at collection.

This fixture proves the pattern bottega uses to avoid that — a **per-feature
`Registry()`** in each conftest, routed to `run_execution` by an autouse fixture (the
generated test calls `run_execution(_IR_PATH, s, e)` with no registry, so it would
otherwise use the empty global). See `glue/subtract_conftest.py`.

It also proves the handlers must **read example values from the IR row** (`ex[...]`),
never hardcode them: `gherkin-mutator` mutates the example cells, and IR-reading
handlers kill every mutant.

Glue-only, no kit change. The fix is NOT "pass `registry=` into `run_execution`" — the
generator emits `run_execution(_IR_PATH, s, e)` with no registry arg. Instead: a
per-feature `Registry()` avoids the import-time duplicate-step collision, and because
`run_execution` resolves `reg = registry or default_registry` at CALL time, a per-test
autouse fixture monkeypatches `aps_kit.runtime.default_registry` to this feature's
registry (undone after each test). Changing the generator to thread `registry=` would
be a kit change for zero gain.

## Run

```sh
./run.sh          # needs uv + curl + network (pins aps-kit + the gherkin binaries @ v0.1.0)
```

## Verified output (this fixture, kit v0.1.0)

```
### gate: both shared-step features collect + run in ONE pytest invocation
3 passed in 0.01s
### acceptance mutation (fresh work-dir, clean feature) — expect survived=0
total=6 killed=6 survived=0 errors=0
```

Swap each conftest's per-feature `Registry()` back to `aps_kit.default_registry` and
the gate instead dies at collection with
`ValueError: duplicate step handler: 'a calculator'` — the bug this guards against.

## Notes
- `gherkin-mutator` writes a manifest stamp **into the `--feature` file** and caches
  per `--work-dir`; differential skipping is keyed on both. `run.sh` mutates a fresh
  copy with a fresh work-dir so the authoritative `total=N killed=N` run is
  reproducible and the committed feature stays pristine.
- `run.sh` builds the venv, binaries, and generated tests in an **external temp dir**
  (auto-removed), so running the regression never plants symlinks or build artifacts
  under the bundle — the omnigent bundle extractor rejects links.
