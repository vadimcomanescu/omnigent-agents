// tinycalc — a deliberately tiny calculator used as a bottega target project.
// `add` is implemented (baseline, green). `multiply` is intentionally absent:
// it is the behavior a bottega slice is meant to deliver.
// See test/tinycalc.test.ts.

export function add(a: number, b: number): number {
  return a + b;
}
