# blackbox-harness (`bbh`)

A test harness for BLACK-BOX systems under deterministic, scripted input —
an emulated arcade board, a console, a simulator, a firmware image, anything
that can be driven frame by frame and whose state can be hashed. It was
extracted from Project VAMPIRE SAVED (a CPS-2 ROM hack with, at extraction in 2026-09, 304 gates and 4,000
frozen expectations and a release policy of "anything red, anything skipped
is a hard fail") by asking of every piece: *would this still be true if the
thing under test were not that ROM, not CPS-2, not even a game?* What
survived is here; what did not stayed there.

## What it gives a consumer project

| piece | what it does | status |
|---|---|---|
| **the verdict classifier** (`lib/sh/classify.sh`) | PASS / SKIP / FAIL / TIMEOUT from an exit status and a log — exit status decides FIRST, SKIP is only ever exit 0 plus a marker, an exit 0 after the shell's own error line is a crash, a killed gate is TIMEOUT not FAIL | H1 |
| **the pre-commit chain** (`bbh run-static`) | every gate that needs no instrument, in two tiers (portable / static), tallied separately, `--strict`, an anti-orphan report, a working-tree snapshot | H1 |
| **the tier classifier** (`bbh tier`) | **[BBH-23]** which gates reach an instrument — transitively, through sourced libs — so none falls between the runners | H1 |
| **the demand-after-trap lint** (`bbh demand-after-trap`) | the `${VAR:?}`-after-`trap … EXIT` shape that exits 0 on macOS bash 3.2 | H1 |
| **the gate contract and prologue** (`docs/gate_contract.md`, `lib/sh/prologue.sh`) | what a gate looks like so the runners can read it | H1 |
| **the comparison classes** (`lib/py/bbh/compare_*.py`, `check_diverge.py`, `describe_masked_shape.py`, `docs/method/oracle_classes.md`) | exact / flicker-tolerated / frozen first-divergence / bounded re-convergent window / composite — the thresholds declared ONCE (`thresholds.py`, consumer-overridable), the log grammar parsed once (`logfmt.py`), a proposer that cannot disagree with the enforcers | H2 |
| **the masked vocabulary** (`lib/sh/masked_compare.sh`, `enumerate_expectations.sh`) | `<class> <baseset> <args>` spec lines dispatched to the right checker with verdict text frozen; the baseset-vs-mask guard; every expectation KIND named | H2 |
| **fingerprint → expectation set** (`lib/py/bbh/fingerprint.py`, `bbh fingerprint`) | the PROGRAM key (the program members, in order, of the first image on the search path) and the WHOLE-SET key (every member in the build's own directory); a registry maps either to a set, whole-set first and program loudly; three kinds (zip members, one file, a command) | H3 |
| **the suite runner** (`bbh run-suite`) | fingerprint the build → its expectation set; every replay run twice through the driver; dispatch `.skip` → `.pending` (a FAIL) → `.masked` → `.diverge` → `.sha1` → NO-EXPECTATION; `--freeze`; a hermetic environment; verdict text frozen to the lineage's | H3 |
| **the driver contract and the fake driver** (`drivers/README.md`, `drivers/fake.sh`, `example/fakesys/fakesys.py`) | `<set> <replay> <out> [sandbox]` + the replay-family environment; a driver that cannot honour a variable REFUSES; a deterministic fake machine whose features produce every expectation class, so the whole chain runs without a ROM | H3 |
| **the `.rpl` grammar** (`lib/py/bbh/rpl.py`, `bbh rpl`) | the replay parser, one copy on the python side (the Lua twin comes with H6) | H3 |
| **the sweep runner** (`bbh run-sweep`) | every instrument-tier gate from the sweep registry, in lanes; the prereq lane first and serial, a red there stops the run; scope and cadence columns, `--freeze` naming what it dropped; `%PLACEHOLDER%` args and `VAR=value` environment; per-row timeouts; `--jobs` with per-slot scratch; `--resume`; the banner that IDENTIFIES the builds (fingerprinted) and the instruments; the anti-orphan check both ways | H4 |
| **expectation and gate hygiene** (`bbh provenance`, `bbh header-defaults`, `bbh ref-rot`, `bbh gate-index`; `lib/sh/shadow_tools.sh`, `lib/sh/accounting.sh`) | every frozen expectation file has a row in a register naming a CLOSED evidence class (a red gate is a question, and its first question is which side rests on a measurement); a gate's header names the default its CODE uses; a hard-coded path default that exists but is too old is ROTTED (absent is not rotted; currency is reported, never failed); the gate index is GENERATED from the headers and a family TSV, complete both ways; a perturbation control edits a shadow copy, never the tracked tool; a battery cannot print GREEN while a gate self-skipped — the one header parser (`gate_header.py`) under all of it | H5 |
| **the MAME Lua layer under a MACHINE PROFILE, the real drivers, the recording corpus** (`lua/mame/`, `drivers/mame.sh`, `mame_guarded.sh`, `fbneo.sh`, `bbh inp-play`, `bbh inp-corpus`, `docs/lua.md`) | the replay engine (per-frame RAM hashes, masks as a basis, dumps, pokes, snapshots, a video log, the always-on input-integrity assertion with its must-fire), the crash guard (`-debug` breakpoints on the vectors, or cheap-mode PC classification), the taps and the recording guard — every board literal (CPU, space, RAM window, port map, exception frame, exception store) in ONE Lua table per board (`profiles/cps2.lua`, `cps2w.lua`, `TEMPLATE.lua`), the grammar in ONE module whose parse equals `rpl.py`'s; headless, sandboxed, input-isolated drivers that REFUSE what they cannot honour; recordings replayed under the guard at every freeze, a dead playback never read as clean | H6 |
| **the skills lock and the guide generator** (`bbh check-skills`, `bbh skill-guide`, `lib/py/bbh/checkskills.py`, `gen_skill_guide.py`) | a SKILL — an agent-facing distillation of the docs that loads BEFORE the work — is ID-locked to the paragraph each rule distils (anchored `**[PFX-N]**`, both ways), names no forbidden token (a game, a build, a board, another skill's IDs), quotes no number that is not in a log (a page or its `_history.md` twin), and its GUIDE.md — the same rules with the incident behind each — is GENERATED from those paragraphs; `[skills]` + one `[skill_<PFX>]` table per skill | H10 |
| **mapped-field comparison at anchors, and dump completeness** (`bbh compare-fields`, `bbh check-dumps`) | **[BBH-80]** the dual-implementation protocol: two implementations traverse identical states on different frame indices, so the comparable thing is the MAPPED state (a fields TSV) at the debounced rising edge of a predicate on the dumped RAM, at the anchor and at offsets after it — `--exact` for same-implementation runs; the predicate, the bases and the debounce are the consumer's `[fields]`; and because the comparator GLOBS, the producer asserts the dump set is complete first (a hole silently moves an anchor) | H7 |

Every piece ships with its ground truth under `selftest/` — ROM-free, no
emulator — and most selftests carry a MUST-FIRE control: an input perturbed
so the check must fail for the stated reason, because a check that passes
for the wrong reason is a failure.

## Quick start

```sh
git clone https://github.com/DefinitelyFrenchName/blackbox-harness ~/Developer/blackbox-harness
cd ~/Developer/blackbox-harness
bin/bbh selftest                      # the harness's own gates, ~6 min with the lineage tree present (350 s measured 2026-09-07; its fidelity checks SKIP without it, ~2 min); BBH_FIDELITY_F5=1: every masked spec, +3 min
cd example && ../bin/bbh run-static   # the example consumer, GREEN
FAKE_ROOT=. ../bin/bbh run-static     # …with its static tier
FAKE_ROOT=. FAKE_ROMPATH=roms/build-a ../bin/bbh run-suite   # the replay suite on a fake build (example/README.md)
FAKE_ROOT=. ../bin/bbh run-sweep --scope all   # the instrument-tier sweep: prereq + fake lanes
../bin/bbh doctor --config bbh.toml   # can this host run it?
ln -s ~/Developer/blackbox-harness/skill/blackbox-harness ~/.claude/skills/blackbox-harness   # the SKILL, loaded by every session on this machine
```

Then in your project: copy `bbh.toml.example` to `bbh.toml`, name your gates
dir and registries, run `bbh run-static --config bbh.toml`. `docs/config.md`
lists every key with its default and the bin it came from; `docs/conventions.md`
is the register of the harness's ruled defaults (where it lives, what travels,
which drivers, the one classifier, the loud re-baseline rule); `example/` is a
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
bin/        bbh (dispatcher), bbh-run-static, bbh-run-suite, bbh-run-sweep, bbh-classify, bbh-doctor, bbh-inp-play, bbh-inp-corpus
lib/sh/     classify.sh registry.sh config.sh prologue.sh masked_compare.sh enumerate_expectations.sh shadow_tools.sh accounting.sh mame_sandbox.sh
lua/mame/   profile.lua rpl_parse.lua rpl_dump.lua replay.lua replay_guard.lua inp_guard.lua snapshot_frames.lua trace_writes.lua tap_writes.lua read_tap.lua
            profiles/ (cps2.lua cps2w.lua TEMPLATE.lua) — the MACHINE PROFILES (docs/lua.md)
lib/py/bbh/ config.py toml_subset.py tier.py demand_after_trap.py thresholds.py logfmt.py fingerprint.py rpl.py
            compare_flicker.py compare_window.py compare_composite.py check_diverge.py describe_masked_shape.py
            gate_header.py gen_gate_index.py header_defaults.py ref_rot.py provenance.py compare_fields.py check_dumps.py
drivers/    README.md (THE DRIVER CONTRACT), fake.sh, mame.sh, mame_guarded.sh, fbneo.sh
selftest/   run.sh + test_*.sh (incl. test_fidelity_vampire.sh, the lineage fidelity checks F1/F3/F4/F5/F6/F7/F9/F10
            and F2 opt-in, and test_fidelity_mame.sh, F8 on the real emulators — opt-in, BBH_MAME_FIDELITY=1)
example/    a complete tiny consumer: fakesys/ (the fake machine + ROM generator), roms/, replays/, expected/, tests/
            (+ consumers/ for real ones); tests/fields.tsv + g_fields.sh: the dual-implementation protocol on the fake
skill/      blackbox-harness/{SKILL.md, GUIDE.md} — the agent-facing distillation of these docs ([BBH-1..87], locked by
            bbh check-skills, the guide GENERATED) and skills.toml, its lock config; symlink the directory into ~/.claude/skills/
docs/       doctrine.md gate_contract.md config.md hygiene.md lua.md conventions.md rebaselines.md method/oracle_classes.md
            <name>_history.md twins carry a page's complete LOG (docs/doctrine.md §3); the page stays lean
```

License: GPL-3.0 (the lineage's).
