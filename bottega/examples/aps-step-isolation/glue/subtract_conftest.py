# Per-feature step-handler glue for features/subtract.feature.
# The specifier authors one of these per slice INTO its generated acceptance dir.
# Key points (regression-proven):
#   - build a PER-FEATURE Registry(), never aps_kit.default_registry, so two
#     features that share a step text (here: "a calculator") do not collide at
#     pytest collection (Registry.step() raises on a duplicate text);
#   - an autouse fixture routes run_execution's default registry to THIS feature's
#     registry (the generated test calls run_execution without a registry arg);
#   - handlers read every value from the IR example row `ex`, never hardcoded, so
#     gherkin-mutator (which mutates the example cells) actually kills the mutants.
import os
import sys

import pytest

import aps_kit.runtime as _rt
from aps_kit.registry import Registry

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "sut"))
from calc import Calculator  # noqa: E402  (system under test)

registry = Registry()


@registry.step("a calculator")
def _given(world, ex):
    world["calc"] = Calculator()


@registry.step("I subtract <b> from <a>")
def _when(world, ex):
    world["result"] = world["calc"].subtract(int(ex["a"]), int(ex["b"]))


@registry.step("the result is <expected>")
def _then(world, ex):
    assert world["result"] == int(ex["expected"])


@pytest.fixture(autouse=True)
def _use_feature_registry(monkeypatch):
    monkeypatch.setattr(_rt, "default_registry", registry)
