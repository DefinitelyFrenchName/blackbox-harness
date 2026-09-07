# Re-baselines — every time the fidelity contract's expected text moved

One dated line per verdict-text or classifier change that re-baselined a
fidelity row (`docs/conventions.md` 10). Newest first; the newest line is
printed at the head of every `selftest/test_fidelity_vampire.sh` run, so a
re-baseline is never silent. The format is the line below: date, the rows,
what moved and why, the two commits (harness first — it is pushed first).

- 2026-09-07 F1: the lineage's static runner gained the exit-0-after-shell-error branch (its 14z-139 gave its three runners ONE classifier), so F1 asserts identity on the shell-crash gate instead of the known delta; harness `3eff2d4`, lineage `ae646787`.
