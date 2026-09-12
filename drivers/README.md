# The driver contract — how the suite drives a machine

**[BBH-25]** A DRIVER runs one replay on one machine and writes one checksum log. The
suite runner (`bbh run-suite`), the comparators and the fidelity checks
never know which machine is behind it; they know this contract. Every
driver in this directory — and any a consumer writes — has the same four
arguments, honours the same environment, and writes the same grammar.

## 1. The invocation

```
<driver> <set> <replay.rpl> <out.log> [sandbox]
```

| argument | meaning |
|---|---|
| `set` | the machine's image name — the emulator's set name, the fake's `<set>.zip` |
| `replay.rpl` | the input script (`lib/py/bbh/rpl.py` is the grammar); a relative path is made absolute before the machine sees it |
| `out.log` | **[BBH-27]** the checksum log to write; made absolute; **removed before the run** so "no END line" can never be satisfied by a previous run's file |
| `sandbox` | **[BBH-36]** optional: a directory the machine may treat as its home (cfg, nvram, snapshots, its own stderr log); made absolute; a fresh temp dir when omitted |

**[BBH-26]** The build under test is what the driver's SEARCH PATH resolves: the
variable is the driver's own (`MAME_ROMPATH`, `FBNEO_ROMPATH`,
`FAKE_ROMPATH`) and the suite names it in `[suite].rompath_env`, falling
back to the reference-input variable (`[suite].input_env`, the lineage's
`ROMDIR`). A driver documents its variable in its header.

## 2. The environment — the replay family (every driver)

| variable | meaning | on a driver that cannot honour it |
|---|---|---|
| `MASK_RANGES` | **[BBH-30]** `lo-hi,...` hex OFFSETS from the checksum window's base, end exclusive; masked bytes are SKIPPED from the hash, so a mask defines a BASIS (a log under one mask is never comparable to a log under another) | REFUSE (the crash guard's precedent: its `-debug` timeline is not checksum-comparable, so it refuses a mask rather than emit a log a gate would compare) |
| `DUMPS` | `frame:lo-hi;...` — at the END of frame N, the RAM range to `dump_<frame>_<lo>.bin` beside the log | REFUSE |
| `POKES` | `frame:addr:hexbytes;...` — scheduled RAM writes, applied at the start of the frame | REFUSE |
| `SNAP_FRAMES` | `f,f,...` — a snapshot of the screen at those frames, into the sandbox | REFUSE |
| `VIDEO_OUT` | **[BBH-31]** a path: a SECOND hash log over the framebuffer, same grammar, written to a separate file so no RAM expectation moves (a RAM-only gate is structurally blind to the whole video path) | REFUSE |
| `INPUT_OUT` | a path: per-frame raw port values `<frame> <p...>` — the detector for host input leaking into the emulated controls | REFUSE |
| `TAIL_FRAMES` | frames to keep running after the last scripted input (default 120) | honour |
| `NO_INPUT_CHECK` | disables the input-integrity assertion (analysis only) | honour or REFUSE, never ignore |
| `INPUT_INJECT_TEST` | **[BBH-32]** `<frame>`: the assertion's MUST-FIRE control — the machine simulates a foreign press and the log must carry an `INPUT-VIOLATION` line | honour if the assertion exists |

**[BBH-29]** The guard family — `GUARD_DEBUG`, `GUARD_PROBE`, `GUARD_PROBE_COND`,
`GUARD_TRACE`, `GUARD_PC_LOG`, `GUARD_BREAK`, `GUARD_MATCH`,
`CRASH_VECTORS`, `CODE_RANGES` — belongs to the GUARDED drivers
(`mame_guarded.sh`). A plain driver REFUSES them.

**[BBH-28]** **THE RULE: a driver that cannot honour a variable REFUSES it — prints
`REFUSED: <driver> cannot honour <VAR> (<why>)` and exits 3 — and never
ignores it.** A caller that set the variable is measuring something; a run
that silently did not measure it is the false green every gate here exists
to remove. (The lineage's FBNeo driver has no `MASK_RANGES`; the lineage
passed masks to it for a session before a gate noticed the logs were
unmasked.)

**[BBH-35]** The suite scrubs `[suite].hermetic_unset` from its environment before any
driver runs, so nothing from the caller's shell reaches a frozen
expectation.

## 3. The output — the log grammar

```
<frame> <hash>        one line per frame, frame 1 first; hash = the state at the END of the frame
...
INPUT-VIOLATION <n> <detail>    only if the integrity assertion fired; BEFORE END, where every consumer trips on it
END <n>               last; n = the number of frames run
```

**[BBH-33]** `<hash>` is any fixed-width hex token the machine computes over its
checksum window minus the mask; the harness compares tokens, never
interprets them. The guarded grammar adds `CRASH <frame> <vector> PC <pc>`,
`REGS …`, `STACK …`, `PCWEEDS …`, `SOFTRESET …` and ends with `END-CRASH
<frame>` instead of `END`. `lib/py/bbh/logfmt.py` is the one reader.

## 4. The exit status

| exit | meaning |
|---|---|
| 0 | **[BBH-34]** the log is complete (`END` present) and carries no `INPUT-VIOLATION` |
| 1 | the machine failed, the log has no `END`, or an `INPUT-VIOLATION` was written — the driver prints the machine's own log and the run is DISCARDED (never compared against anything) |
| 2 | the guard tripped (`CRASH` / `PCWEEDS` / `SOFTRESET` / `END-CRASH`): the log is the bug report |
| 3 | a variable was REFUSED |

## 5. The drivers here

| driver | machine | search path | notes |
|---|---|---|---|
| `fake.sh` | `example/fakesys/fakesys.py` | `FAKE_ROMPATH` (or `FAKE_ROOT`) | honours the whole replay family; refuses the guard family; `FAKE_BUILD`, `FAKE_NONDET`, `FAKE_CRASH_AT` are its own knobs |
| `mame.sh` | MAME + `lua/mame/replay.lua` under a MACHINE PROFILE (`BBH_PROFILE`, required: a name under `lua/mame/profiles/` or a path) | `MAME_ROMPATH` (falls back to `ROMDIR`); `MAME_BIN` names the binary | honours the whole replay family; refuses the guard family. Headless and sandboxed (`lib/sh/mame_sandbox.sh`): every host input provider off, `SDL_VIDEODRIVER=dummy`, a fresh cfg/nvram/diff/snap/sta/home per run |
| `mame_guarded.sh` | MAME + `replay_guard.lua` (crash detection: `-debug` breakpoints on the exception vectors, or cheap-mode PC classification with `GUARD_DEBUG=0`) | as `mame.sh` | honours the guard family; refuses `MASK_RANGES`, `NO_INPUT_CHECK`, `VIDEO_OUT`, `INPUT_OUT`; exit 2 when it trips |
| `fbneo.sh` | **[BBH-37]** a patched FBNeo frontend carrying the replay harness (`-hinput/-hout/-hdump`, `FBNEO_HPOKE`, `FBNEO_HVIDEO`) — a SECOND implementation of the same machine | `FBNEO_ROMPATH` (first wins; `ROMDIR` always last), built as a symlink overlay because the frontend has no `-rompath`; `FBNEO_BIN` required | maps `DUMPS` to `-hdump` (files `<out>.dump_<f>_<a>.bin`), `POKES` to `FBNEO_HPOKE`, `VIDEO_OUT` to `FBNEO_HVIDEO`; refuses `MASK_RANGES`, `SNAP_FRAMES`, `INPUT_OUT`, `INPUT_INJECT_TEST`, `NO_INPUT_CHECK`, a `TAIL_FRAMES` other than the frontend's 120, and the guard family |

The MAME drivers' Lua side, the machine profile and the other instruments
(taps, snapshots, the recording guard) are `docs/lua.md`.

Ground truth: `selftest/test_driver_contract.sh` exercises every row of
§2 and §4 against `fake.sh`, including the refusal and the must-fire
control of the integrity assertion; `selftest/test_mame_drivers.sh` the sh
half of the three real drivers against a STUB emulator (every refusal,
every path made absolute, every isolation flag, the stale-artifact rule,
the exit codes); fidelity F8 (`selftest/test_fidelity_mame.sh`, opt-in)
the Lua half on the real emulators — the lineage's driver and `mame.sh`
produce byte-identical logs.
