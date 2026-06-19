class Calculator:
    @staticmethod
    def _num(x):
        try:
            return float(x)
        except (TypeError, ValueError):
            raise TypeError(f"not a number: {x!r}")

    def add(self, a, b):
        return self._num(a) + self._num(b)

    def divide(self, a, b):
        return self._num(a) / self._num(b)
