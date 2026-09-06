# The example consumer — a complete tiny project on a fake machine

Everything the harness does, exercised on a machine that needs no ROM, no
emulator and no board: `fakesys/fakesys.py`, 64 KiB of RAM driven frame by
frame by `.rpl` replays through `drivers/fake.sh` (the driver contract,
`drivers/README.md`). Five ROM images under `roms/` (generated, byte-
reproducible: `fakesys/make_roms.py`), six replays, an expectation tree with
every kind and class (`expected/README.md`), a handful of gates.

## Run it green

```sh
cd example
../bin/bbh run-static                                  # the portable tier
FAKE_ROOT=. ../bin/bbh run-static                      # + the static tier
FAKE_ROOT=. FAKE_ROMPATH=roms/build-a ../bin/bbh run-suite   # the suite on the hooked build
FAKE_ROOT=. FAKE_ROMPATH=roms/base    ../bin/bbh run-suite   # …on the base machine
FAKE_ROOT=. FAKE_ROMPATH=roms/hook    ../bin/bbh run-suite   # …on an UNREGISTERED image: exit 1, loudly
```

The suite output on `build-a` shows one line per class:

```
build fingerprint -> expectation set 'build-a'
per-set mask: ff00-10000
01_idle                  PASS masked-exact
02_coin_start            PASS masked-window (divergent frames 100, runs 1, window 260..359, 261 identical after)
03_press                 PASS masked-flicker (FLICKER 2 100,250 — frozen inventory)
04_both                  PASS masked-composite (divergent frames 101 in 2 run(s): flicker 220, windows 260-359, 261 identical after)
05_attract               PASS (diverges from base/masked at exactly 900)
06_other_set             SKIP (targets the other image; covered by its own suite)
SUITE GREEN
```

## Break a control, watch it fire

```sh
echo 'flicker base/masked 2 100,251' > expected/build-a/03_press.masked   # move one frozen frame
FAKE_ROOT=. FAKE_ROMPATH=roms/build-a ../bin/bbh run-suite               # 03_press FAIL masked-flicker … SUITE RED
git checkout -- expected/build-a/03_press.masked
FAKE_NONDET=1 FAKE_ROOT=. FAKE_ROMPATH=roms/base ../bin/bbh run-suite     # NONDETERMINISTIC on every replay
POKES=50:1000:ff FAKE_ROOT=. FAKE_ROMPATH=roms/base ../bin/bbh run-suite  # still GREEN: the suite scrubs its environment
```

## Freeze

```sh
FAKE_ROOT=. FAKE_ROMPATH=roms/base ../bin/bbh run-suite --freeze    # rewrites base/*.sha1 + base/logs/
./make_expected.sh                                                   # the whole tree, from scratch, with its provenance
```

## What the fake machine is

| feature (the ROM's `features=` line, or `FAKE_BUILD=`) | what it does | the class it produces |
|---|---|---|
| (none) | the base machine | exact / `.sha1` |
| `hook` | one byte written a frame LATE on every player-button press; "cycle-cost" noise in `$FF80-$FFFF` every frame (the region the mask covers) | flicker |
| `select` | after 1P start, one byte held for frames +60..+159, then restored | window |
| `attract` | the attract demo (frame 900 on, no coin) diverges permanently | diverge (`.diverge` kind unmasked, `diverge` class masked) |
| `hook,select` (`both`) | | composite |
| `FAKE_NONDET=1` | the clock mixed in | NONDETERMINISTIC |
| `FAKE_CRASH_AT=n` | `CRASH`/`REGS`/`STACK`, `END-CRASH`, exit 2 | the guarded grammar |

Its ports and tokens are the lineage's (`p1`/`p2`: `U D L R 1-6`; `sys`:
`S1 S2 C1 C2 SV TS`); its checksum window is the whole RAM, so mask offsets
count from 0. `roms/build-a` and `roms/build-b` share every program member
and differ in `fake.gfx` only — the DUAL-KEY case, registered by whole-set
key; `roms/hook` has no registry row on purpose.
