# Frozen expectations — WHERE EACH NUMBER CAME FROM

One row per file directly under `expected/`; `bbh provenance` keeps it
complete both ways (a file with no row fails, a row naming a file that is
gone fails) and refuses a `rests on` cell outside the closed vocabulary
below. The per-set DIRECTORIES are out of its scope: their provenance is
`README.md`'s table plus `make_expected.sh`, which regenerates every one.

**A red gate is a question, and its first question is which side rests on
a measurement.** The evidence classes of this consumer:

- `registry` — a ledger of decisions (which image maps to which set), not a
  measurement.
- `self-frozen` — the driver's own output on the same image, frozen: locks
  CURRENCY, never correctness.
- `authored` — a literal written by a person from a measured shape
  (`bbh describe-shape`), e.g. a `.masked` spec.
- `measured (two runs compared)` — two driver runs under the mask,
  compared, then kept as a basis.

| file | owner | subject | rests on | re-freeze | since |
|---|---|---|---|---|---|
| `registry.tsv` | `bbh run-suite` | which image fingerprint dispatches to which expectation set | registry | rows are added by hand when an image is frozen (`bbh fingerprint --sha-only` / `--set-key`) | H3 |
