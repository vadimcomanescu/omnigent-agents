// Acceptance tests for tinycalc.
//
// `adds` passes today (baseline). `multiplies` fails today on purpose — it is
// the swarmforge starting point: a fresh coder slice implements `multiply` and
// drives this test to green. We reach `multiply` through an `any` cast so the
// missing export fails at runtime inside its own test (and keeps `tsc --noEmit`
// clean) rather than breaking compilation of the whole file.

import { describe, it, expect } from "vitest";
import * as tinycalc from "../src/tinycalc";

describe("tinycalc", () => {
  it("adds", () => {
    expect(tinycalc.add(2, 3)).toBe(5);
  });

  it("multiplies", () => {
    // swarmforge target slice: implement and export tinycalc.multiply.
    expect((tinycalc as any).multiply(2, 3)).toBe(6);
  });
});
