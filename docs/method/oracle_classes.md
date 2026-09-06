# The oracle classes — the ratified comparison vocabulary, and what may never loosen it

A REFERENCE COMPARISON puts the system under test beside a frozen
reference run of the same replay and asks whether the per-frame state
stream is the same. The answer is not always "bit-identical", and the
classes below are the only other answers a consumer's expectation may give.
Each is a MEASURED MECHANISM with a FROZEN expectation; none is a
tolerance. The checkers are `lib/py/bbh/compare_*.py` and
`check_diverge.py`, dispatched by `lib/sh/masked_compare.sh` from a spec
line `<class> <baseset> <args>`; their ground truths are the
`selftest/test_compare_*.sh` and `test_masked_compare.sh` gates. The
thresholds are `lib/py/bbh/thresholds.py`, declared once. (Lineage:
VampireSaved's `docs/project/oracle_classes.md`, v1-v6; the numbers and the
named exemptions stayed there.)

## The basis: masked bytes are SKIPPED, so a mask is a basis, not a flag

A per-frame checksum covers a RAM window minus a MASK — byte ranges the
consumer has ratified as execution-position noise (a dead-stack window, a
sound-latch phase word). Masked bytes are skipped FROM THE CHECKSUM, so
adding a range changes every frame's hash: a reference frozen under one
mask is not comparable to a run under another. Hence the two records and
the guard: a basis directory carries `MASK` (what it was frozen under), a
set may carry `mask` (what it runs under), and `masked_check` REFUSES a
pairing whose two masks differ, or a mask-carrying set citing a record-less
basis. Re-freezing to make that green is the one thing the guard exists to
prevent.

## The classes

| class | spec line | what it asserts | checker |
|---|---|---|---|
| **exact** (default) | `exact <basis> -` | the two logs are byte-identical | `cmp` |
| **flicker-tolerated** (v2) | `flicker <basis> <n> <f1,f2,…>` | the divergent frames are EXACTLY the frozen inventory: each run ≤ `flicker_max` frames, ≥ `reconverge` identical frames after each, ≤ `flicker_max_total` in all; NO end-of-log exemption — a divergence the log ends inside is `FAIL-SHORT`, a different finding (the replay is too short) from `FAIL` (the build diverged) | `compare_flicker` |
| **frozen first-divergence constant** | `diverge <basis> <frame>` | line-identical through `frame−1`, first divergence EXACTLY at `frame`; earlier, later or absent FAILS; a length mismatch FAILS (a short log is never a prefix match) | `check_diverge` — the spec file's STEM names the base log |
| **bounded re-convergent window** (v3) | `window <basis> <onset> <end>` | ONE contiguous divergent run, a FIXED onset, full RE-CONVERGENCE (≥ `reconverge` identical frames after), the end state untouched; a bit-identical pair FAILS — the expectation asserts the divergence EXISTS | `compare_window` |
| **composite** (v4) | `composite <basis> <f1,…> <onset-end;…>` | the strict CONJUNCTION of flicker and window: every divergent run accounted for BY NAME, the flicker set equal to its frozen inventory, the window list exact, full re-convergence; adds NO tolerance — it is stricter than either component | `compare_composite` |

Two rulings that travel with the classes:

- **The ≥ `reconverge` rule is INTRA-mechanism** (v5): it governs the tail
  after the last divergence of ONE mechanism and does not bind across the
  gap between two separately attributed ones. `--min-converge-flicker` makes
  it bind between flicker runs; it is OFF by default and a consumer that
  turns it on is amending its policy.
- **A divergence that does not re-converge is NOT expressible** in this
  vocabulary. The proposer (`describe_masked_shape`) says so and proposes
  nothing; the shape is root-caused, never absorbed into a widened
  tolerance.

## What may never loosen a class

1. **A replay is reclassified to a looser class only with a NEW MEASURED
   MECHANISM and the consumer's sign-off** — never to make a red green.
2. **The standing watch:** flickers growing beyond the frozen inventory, or
   divergences turning systematic, mean STOP AND ROOT-CAUSE. That pattern
   is a deeper issue, not tolerance noise. A grown inventory FAILS; so does
   a SHRUNK one — drift either way is loud, because a frozen expectation
   describes ONE build and a fresh build that differs is not that build.
3. **The proposer and the enforcers cannot disagree:** they import the same
   thresholds, and `selftest/test_thresholds.sh` proves that a consumer
   override reaches both (a proposed line must drop into a spec verbatim
   and pass).
4. **Whole-state frame-exact remains the standard** for reference runs,
   run-to-run determinism and hook-free builds; the non-exact classes exist
   because zero-cost hooking is impossible on a real engine — a hook on a
   path the reference executes costs cycles, and interrupts then land at
   skewed instruction boundaries in otherwise-identical frames.

## Where a class is written

A set directory holds one expectation per replay:
`<set>/<name>.masked` (a spec line above), `.skip` (deliberately not run,
with a reason), `.sha1` (self-frozen to ONE image — it answers "did this
build change since I froze it" and can never see a regression against the
reference), `.pending` (no ratified class yet — REPORTED as unevaluated,
never silently skipped: `enumerate_expectations` returns non-zero on it).
A new KIND is registered in `enumerate_expectations.sh` and nowhere else.
