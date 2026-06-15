"""Acceptance tests for tinycalc.

`test_add` passes today (baseline). `test_multiply` fails today on purpose — it
is the bottega starting point: a fresh coder slice implements `multiply` and
drives this test to green. We reference attributes through the module so the
missing `multiply` raises AttributeError inside its own test rather than an
import error that would break the whole suite.
"""

import tinycalc


def test_add():
    assert tinycalc.add(2, 3) == 5


def test_multiply():
    # bottega target slice: implement tinycalc.multiply so this passes.
    assert tinycalc.multiply(2, 3) == 6
