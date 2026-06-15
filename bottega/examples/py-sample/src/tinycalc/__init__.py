"""tinycalc — a deliberately tiny calculator used as a bottega target project.

`add` is implemented (baseline, green). `multiply` is intentionally absent: it is
the behavior a bottega slice is meant to deliver. See tests/test_tinycalc.py.
"""


def add(a: float, b: float) -> float:
    """Return the sum of two numbers."""
    return a + b
