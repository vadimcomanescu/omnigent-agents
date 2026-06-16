# aps-equivalent-mutants — the equivalent-mutant classification gate

`gherkin-mutator` mutates example **cells**, but some mutations cannot change a
scenario's outcome — they are **equivalent mutants** and are inherently unkillable.
A literal `survived=0` acceptance-mutation gate is therefore **unsatisfiable** for any
realistic feature with input validation or error handling, even when the step glue
correctly reads operand values from the IR (not hardcoded).

`features/validation.feature` has two scenarios that produce real survivors:

| mutation | result | why |
|----------|--------|-----|
| `scenarios[0].examples[0].a: x -> X` | **survived** | type-only "rejects non-numeric" assertion — non-numeric → non-numeric still raises `TypeError`; the value is not outcome-determining (**equivalent**) |
| `scenarios[0].examples[0].b: y -> Y` | **survived** | same scenario; `a` is validated first and `b` is also non-numeric → still `TypeError` (**equivalent**) |
| `scenarios[1].examples[0].a: 10 -> 7` | **survived** | zero-divisor scenario (`b=0`); the dividend is irrelevant to `ZeroDivisionError` (**equivalent**) |
| `scenarios[1].examples[0].b: 0 -> -1` | **killed** | the divisor **is** outcome-determining: away from 0 there is no error → test fails → killed |

So the authoritative summary is `total=4 killed=1 survived=3 errors=0`.

## The gate (what architect-verify actually requires)

NOT literal `survived=0`. The architect classifies each surviving mutant:

- **KILLABLE** — the mutated cell IS outcome-determining and the test failed to catch
  it ⇒ a weak/vacuous example or a hardcoded handler ⇒ **BOUNCE** the owning slice.
- **EQUIVALENT** — the mutated cell cannot change the scenario outcome ⇒ acceptable,
  **with a written justification**.

**SIGN-OFF** requires `errors=0` AND **zero killable survivors** AND every equivalent
survivor carries a justification, recorded in the evidence dir (here:
`equivalent-mutants.json`) and the registry `verification` block. **BOUNCE** whenever
there is ≥1 killable survivor. The killed divisor cell above proves the gate is not
"ignore all survivors" — a load-bearing cell that the suite fails to catch still
bounces.

`equivalent-mutants.json` is the recorded classification for this feature (the format
the architect produces).

## Run

```sh
./run.sh          # needs uv + curl + network; builds in an external temp dir
```

Verified output (kit v0.1.0): `2 passed`, then
`total=4 killed=1 survived=3 errors=0` with the three survivors above. The
`--runner-worker` invokes the **venv's** pytest explicitly (`$VENV/bin/aps-adapter
$VENV/bin/pytest …`) so `aps_kit` is importable without any `PATH` surgery.
