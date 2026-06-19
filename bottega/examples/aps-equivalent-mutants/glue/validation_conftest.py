# Per-feature step glue for features/validation.feature. Handlers read operand values
# FROM THE IR row `ex` (never hardcoded) and assert only the EXCEPTION TYPE — so some
# example-cell mutations cannot change the outcome and survive as EQUIVALENT mutants.
import os
import sys

import pytest

import aps_kit.runtime as _rt
from aps_kit.registry import Registry

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "sut"))
from calc import Calculator  # noqa: E402

registry = Registry()


@registry.step("a calculator")
def _given(world, ex):
    world["calc"] = Calculator()


@registry.step("I add <a> and <b>")
def _add(world, ex):
    try:
        world["result"], world["exc"] = world["calc"].add(ex["a"], ex["b"]), None
    except Exception as e:  # noqa: BLE001
        world["exc"] = e


@registry.step("I divide <a> by <b>")
def _divide(world, ex):
    try:
        world["result"], world["exc"] = world["calc"].divide(ex["a"], ex["b"]), None
    except Exception as e:  # noqa: BLE001
        world["exc"] = e


@registry.step("it raises a type error")
def _type_error(world, ex):
    assert isinstance(world["exc"], TypeError)


@registry.step("it raises a zero division error")
def _zero_div(world, ex):
    assert isinstance(world["exc"], ZeroDivisionError)


@pytest.fixture(autouse=True)
def _use_feature_registry(monkeypatch):
    monkeypatch.setattr(_rt, "default_registry", registry)
