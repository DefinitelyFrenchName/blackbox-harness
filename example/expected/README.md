# The example's expectation tree

Every file here is produced by `example/make_expected.sh` from the fake ROM
images under `example/roms/` (which `example/fakesys/make_roms.py`
generates, byte-reproducibly). Nothing is hand-placed; the AUTHORED
expectations (the `.masked` specs, the `.diverge`, the `.skip`, the
per-set `mask`) are literals in that script, so the provenance of each
frozen number is one `grep` away.

| path | kind | produced by |
|---|---|---|
| `registry.tsv` | fingerprint → set | `bbh fingerprint --sha-only` (base, attract) and `--set-key` (build-a, build-b) |
| `base/*.sha1`, `base/logs/` | self-frozen, unmasked | `bbh run-suite --freeze` on `roms/base` |
| `base/masked/MASK`, `base/masked/logs/` | THE MASKED BASIS | two driver runs per replay under the example's mask, compared, then copied |
| `attract/*.sha1`, `attract/logs/` | self-frozen | `--freeze` on `roms/attract` with `SUITE_ONLY` excluding 05 |
| `attract/05_attract.diverge` | frozen first-divergence constant, unmasked | authored: `base 900` |
| `build-a/*.masked`, `build-a/mask`, `build-a/06_other_set.skip` | the masked vocabulary | authored from `bbh describe-shape` over the measured pairs |
| `build-b/` | the dual-key twin | a copy of `build-a/` |
| `PROVENANCE.md` | the register `bbh provenance` keeps complete (the FILES directly under `expected/`, i.e. `registry.tsv`) | by hand, one row per file |

The images `roms/hook` has NO row: it is the unregistered build the suite
must refuse loudly (exit 2 from the fingerprint, `unregistered build
fingerprint — see message above` from the suite).
