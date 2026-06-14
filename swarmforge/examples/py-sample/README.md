# py-sample — swarmforge Python target

A minimal Python project for exercising the swarmforge pipeline.

- `src/tinycalc/__init__.py` — `add` is implemented (baseline).
- `tests/test_tinycalc.py` — `test_add` passes; **`test_multiply` fails on
  purpose**. That red test is the pipeline's starting point: a swarmforge slice
  implements `tinycalc.multiply` and drives it to green.

Stack detection: the conductor sees `pyproject.toml` and selects the Python
toolchain.

Gates (the conductor prefers these, falling back to defaults):

```
pytest          # tests   -> 1 passed, 1 failed (the multiply target)
ruff check .    # lint
mypy            # typecheck
```

No install step: `[tool.pytest.ini_options] pythonpath = ["src"]` lets
`import tinycalc` resolve from source.
