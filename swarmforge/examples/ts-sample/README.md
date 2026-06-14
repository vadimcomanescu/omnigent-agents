# ts-sample — swarmforge TypeScript target

A minimal TypeScript project for exercising the swarmforge pipeline.

- `src/tinycalc.ts` — `add` is implemented (baseline).
- `test/tinycalc.test.ts` — `adds` passes; **`multiplies` fails on purpose**.
  That red test is the pipeline's starting point: a swarmforge slice implements
  and exports `multiply` and drives it to green.

Stack detection: the conductor sees `package.json` and selects the TS toolchain.

Gates (the conductor prefers the package scripts, falling back to defaults):

```
npm install      # one-time: pull vitest + typescript
npm test         # tests     -> vitest: 1 passed, 1 failed (the multiply target)
npm run lint     # lint      (eslint; add a config to enable)
npm run typecheck# typecheck (tsc --noEmit)
```

`node_modules/` is gitignored; run `npm install` before the gates.
