# Conventions — history (the complete log behind `docs/conventions.md`)

The twin of `docs/conventions.md` (`docs/doctrine.md` §3): dated
measurements, withdrawn drafts and the narrative behind each ruled
default. Newest first. No anchor lives here.

## 2026-09-07 — the eight defaults ruled

- **The rulings.** The lineage's maintainer ruled on every default of its
  `harness_scope.md` §7 in one sitting, each measured in the harness as it
  stood: keep the separate repository found by `$BBH_HOME`; the license is
  load-bearing, not a default; citations travel, no anchor does (33 session
  and 23 issue citations counted; ONE lineage rule ID, `[CPE-24]`, in four
  places as `[sweep].prereq_cite`'s default); four drivers, the FPGA lane
  stays with its consumer (its lane measured: 584 lines, 44 board-and-romset
  couplings, dumps rather than the log grammar); documentation tools out;
  the consumer config kept here with its location passed as an input; one
  classifier; the loud re-baseline rule.
- **F2, first run: IDENTICAL.** The whole live portable tier of the lineage
  through both static runners — `tests/run_all_static.sh --tier portable`
  and `bbh-run-static --config example/consumers/bbh.vampire.toml --tier
  portable` — diffed with durations normalised: identical, 65 PASS rows
  (`BBH_FIDELITY_F2=1 sh selftest/test_fidelity_vampire.sh`). This is the
  figure `docs/conventions.md` 7 quotes.
- **A withdrawn draft.** The consumer-root input was first written as an
  environment override inside the config resolver (`BBH_CONSUMER_ROOT`,
  honoured by `root_of`) and withdrawn within the hour: exported by the
  lineage's gate, it would have reached every other config the same
  fidelity run opens — F1's fake-repo `bbh.toml` and the example's — and
  pointed them at the lineage tree. The input became `BBH_FIDELITY_ROOT`,
  consumed by the fidelity test alone, which derives a private config copy.
- **The selftest's duration, measured:** 350 s across 31 tests with the
  lineage tree present (`test_fidelity_vampire` 106 s, `test_run_sweep`
  57 s, `test_suite_dispatch` 40 s dominate); the README said "~3.5 min"
  from before the fidelity tests existed.
