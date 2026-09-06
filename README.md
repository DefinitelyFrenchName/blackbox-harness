# blackbox-harness (`bbh`)

A test harness for BLACK-BOX systems under deterministic, scripted input —
an emulated arcade board, a console, a simulator, a firmware image, anything
that can be driven frame by frame and whose state can be hashed. It was
extracted from Project VAMPIRE SAVED (a CPS-2 ROM hack with 304 gates, 4,000
frozen expectations and a release policy of "anything red, anything skipped
is a hard fail") by asking of every piece: *would this still be true if the
thing under test were not that ROM, not CPS-2, not even a game?* What
survived is here; what did not stayed there.

## What it gives a consumer project

| piece | what it does | status |
|---|---|---|
| **the verdict classifier** (`lib/sh/classify.sh`) | PASS / SKIP / FAIL / TIMEOUT from an exit status and a log — exit status decides FIRST, SKIP is only ever exit 0 plus a marker, an exit 0 after the shell's own error line is a crash, a killed gate is TIMEOUT not FAIL | H1 |
| **the pre-commit chain** (`bbh run-static`) | every gate that needs no instrument, in two tiers (portable / static), tallied separately, `--strict`, an anti-orphan report, a working-tree snapshot | H1 |
| **the tier classifier** (`bbh tier`) | which gates reach an instrument — transitively, through sourced libs — so none falls between the runners | H1 |
| **the demand-after-trap lint** (`bbh demand-after-trap`) | the `${VAR:?}`-after-`trap … EXIT` shape that exits 0 on macOS bash 3.2 | H1 |
| **the gate contract and prologue** (`docs/gate_contract.md`, `lib/sh/prologue.sh`) | what a gate looks like so the runners can read it | H1 |
| **the comparison classes** (`lib/py/bbh/compare_*.py`, `check_diverge.py`, `describe_masked_shape.py`, `docs/method/oracle_classes.md`) | exact / flicker-tolerated / frozen first-divergence / bounded re-convergent window / composite — the thresholds declared ONCE (`thresholds.py`, consumer-overridable), the log grammar parsed once (`logfmt.py`), a proposer that cannot disagree with the enforcers | H2 |
| **the masked vocabulary** (`lib/sh/masked_compare.sh`, `enumerate_expectations.sh`) | `<class> <baseset> <args>` spec lines dispatched to the right checker with verdict text frozen; the baseset-vs-mask guard; every expectation KIND named | H2 |
| **fingerprint → expectation set** (`lib/py/bbh/fingerprint.py`, `bbh fingerprint`) | the PROGRAM key (the program members, in order, of the first image on the search path) and the WHOLE-SET key (every member in the build's own directory); a registry maps either to a set, whole-set first and program loudly; three kinds (zip members, one file, a command) | H3 |
| **the suite runner** (`bbh run-suite`) | fingerprint the build → its expectation set; every replay run twice through the driver; dispatch `.skip` → `.pending` (a FAIL) → `.masked` → `.diverge` → `.sha1` → NO-EXPECTATION; `--freeze`; a hermetic environment; verdict text frozen to the lineage's | H3 |
| **the driver contract and the fake driver** (`drivers/README.md`, `drivers/fake.sh`, `example/fakesys/fakesys.py`) | `<set> <replay> <out> [sandbox]` + the replay-family environment; a driver that cannot honour a variable REFUSES; a deterministic fake machine whose features produce every expectation class, so the whole chain runs without a ROM | H3 |
| **the `.rpl` grammar** (`lib/py/bbh/rpl.py`, `bbh rpl`) | the replay parser, one copy on the python side (the Lua twin comes with H6) | H3 |
| the sweep runner (lanes, scope, cadence, per-row timeouts, `--jobs`, `--resume`) | H4 |
| expectation provenance, header defaults, reference rot, the gate index | H5 |
| the MAME Lua layer with machine profiles, the MAME / FBNeo drivers, recordings | H6 |
| mapped-field comparison at anchors, dump completeness | H7 |

Every piece ships with its ground truth under `selftest/` — ROM-free, no
emulator — and most selftests carry a MUST-FIRE control: an input perturbed
so the check must fail for the stated reason, because a check that passes
for the wrong reason is a failure.

## Quick start

```sh
git clone https://github.com/DefinitelyFrenchName/blackbox-harness ~/Developer/blackbox-harness
cd ~/Developer/blackbox-harness
bin/bbh selftest                      # the harness's own gates, ~3 min (BBH_FIDELITY_F5=1: every masked spec, +3 min)
cd example && ../bin/bbh run-static   # the example consumer, GREEN
FAKE_ROOT=. ../bin/bbh run-static     # …with its static tier
FAKE_ROOT=. FAKE_ROMPATH=roms/build-a ../bin/bbh run-suite   # the replay suite on a fake build (example/README.md)
../bin/bbh doctor --config bbh.toml   # can this host run it?
```

Then in your project: copy `bbh.toml.example` to `bbh.toml`, name your gates
dir and registries, run `bbh run-static --config bbh.toml`. `docs/config.md`
lists every key with its default and the bin it came from; `example/` is a
complete tiny consumer to copy from; `example/consumers/bbh.vampire.toml` is
the config of the project this harness was extracted from.

## The four bins

Every file here is in one of four bins, and the config schema follows them:

- **code** — true for anything: the classifier, the runners, the registry
  grammar, the log grammar, the comparison classes, the driver contract.
- **config** — a VALUE the consumer declares: paths, the regexes that name
  its instruments, placeholders, thresholds, a mask default.
- **machine profile** — true for a CPU/board: address-space tags, the RAM
  window, the port map, exception vectors (one Lua table per board; H6).
- **stays with the consumer** — anything true of one system only.

## Doctrine (the short form; `docs/doctrine.md` is the long one)

No untested change survives. Every in-instrument measurement becomes a
rerunnable case. Verdict logic is itself tested. A field report is a
RECORDING before it is a theory. SKIP is not PASS. A red gate is a QUESTION
whose first question is which side rests on a measurement. When a claim
changes, grep for the claim.

## Layout

```
bin/        bbh (dispatcher), bbh-run-static, bbh-run-suite, bbh-classify, bbh-doctor
lib/sh/     classify.sh registry.sh config.sh prologue.sh masked_compare.sh enumerate_expectations.sh
lib/py/bbh/ config.py toml_subset.py tier.py demand_after_trap.py thresholds.py logfmt.py fingerprint.py rpl.py
            compare_flicker.py compare_window.py compare_composite.py check_diverge.py describe_masked_shape.py
drivers/    README.md (THE DRIVER CONTRACT), fake.sh
selftest/   run.sh + test_*.sh (incl. test_fidelity_vampire.sh, the lineage fidelity checks F1/F3/F5/F6/F7)
example/    a complete tiny consumer: fakesys/ (the fake machine + ROM generator), roms/, replays/, expected/, tests/
            (+ consumers/ for real ones)
docs/       gate_contract.md config.md method/oracle_classes.md
```

License: GPL-3.0 (the lineage's).
