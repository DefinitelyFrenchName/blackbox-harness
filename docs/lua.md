# The MAME Lua layer — the replay engine, the guards and the taps, under a machine profile

Everything under `lua/mame/` runs inside MAME's Lua (`-autoboot_script`).
It was lifted from Project VAMPIRE SAVED's `tests/lua/` by moving every
literal about the BOARD into one table — the MACHINE PROFILE — and the
replay grammar into one module. The scripts know a CPU tag, an address
space, a RAM window, a port map and an exception-frame layout only through
that table; the cps2 profile is proved by fidelity F8 (the lineage's driver
and `drivers/mame.sh` produce byte-identical logs on the same replay), not
by inspection.

## 1. The machine profile (`lua/mame/profile.lua`, `profiles/*.lua`)

`BBH_PROFILE` names it — a bare name (`cps2`) resolves to
`lua/mame/profiles/<name>.lua`, a path is used as is. `profile.load()`
REFUSES a profile missing a required key, and every guard script refuses
one missing a `crash.*` key it reads; a script never runs on an implied
board. `profiles/TEMPLATE.lua` carries every key with a comment;
`selftest/test_profiles.sh` keeps the template complete (every `P.x` / `C.x`
a script reads is in it) and the loader's required list in step.

| key | read by | meaning |
|---|---|---|
| `cpu`, `space`, `screen` | all | the device tags: `manager.machine.devices[cpu].spaces[space]` is where RAM, pokes and dumps live; `screen` serves `VIDEO_OUT` and snapshots |
| `ram = {lo, hi}` | all | the checksum window, inclusive; `MASK_RANGES` offsets count from `lo`; crash dumps cover it |
| `active_low` | replay, guard | a press CLEARS the field's bits (the lineage's CPS-2); the idle value of every controlled bit is a KNOWN CONSTANT the integrity assertion asserts on frame 1 rather than adopting from a live read |
| `sides` | all | the replay grammar's sides: `who = { width, tokens = { tok = {port tag, field name} } }` |
| `ports` | replay, guard | the input ports the integrity assertion reads and `INPUT_OUT` logs, in log order |
| `inject`, `inject_bit` | replay, guard | `INPUT_INJECT_TEST`'s phantom press: a side/token (replay.lua presses it for one frame) and a bit of `ports[1]` (the guard flips it on its read) |
| `crash.vectors`, `vector_base`, `vector_stride` | guard | which exception vectors to trap under `-debug`, and where the table lives |
| `crash.group0`, `pc_at_sp`, `addr_at_sp` | guards | the exception frame: which vectors carry a fault address, and where the pushed PC and address sit from SP |
| `crash.code = {lo, hi}` | guards | a ROM-plausible long: handler addresses, the STACK sketch. `cps2` (4 MB) and `cps2w` (6 MB) differ ONLY here — the lineage's two guards carried different values and drew different sketches of the same crash |
| `crash.stack_top`, `pc_mask`, `regs`, `sp` | guards | the sketch's ceiling, the address width, the REGS line's register names, the stack pointer's name(s) |
| `crash.exception_store`, `store_to_vector`, `store_code_max`, `arm_frame` | inp_guard | the machine's OWN exception-code store (every handler begins with a store there), `vector = code + store_to_vector`, the filters |
| `crash.match`, `crash.alive` | guard, inp_guard | `GUARD_MATCH`'s in-match flag; the recording guard's ALIVE line |
| `crash.probe_regs`, `trace_regs`, `tap_regs` | guard, taps | optional register lists (68000-shaped defaults) |

## 2. The grammar (`lua/mame/rpl_parse.lua` == `lib/py/bbh/rpl.py`)

One strict parser for every script (the lineage had one strict copy and
five lenient ones that silently DROPPED an unknown token — a malformed
replay now fails loudly, with the lineage's own error texts, on both
sides). Two copies of a grammar are the harness's own rot risk, so their
canonical parses are diffed: `selftest/test_rpl_lua.sh` under a standalone
`lua` (SKIP with the reason when none is present), and fidelity F8 under
MAME's own interpreter over every lineage replay — the production one.
`lua/mame/rpl_dump.lua` and `bbh rpl dump` print that canonical text.

## 3. The scripts

| script | driver | what it measures |
|---|---|---|
| `replay.lua` | `drivers/mame.sh` | THE ORACLE ENGINE: stage inputs per frame, hash the RAM window (FNV-1a64) at the end of every frame, honour `MASK_RANGES` (masked bytes are SKIPPED, so a mask is a BASIS), `DUMPS`, `POKES`, `SNAP_FRAMES`, `VIDEO_OUT`, `INPUT_OUT`; the always-on INPUT-INTEGRITY assertion with its must-fire control (`INPUT_INJECT_TEST`) |
| `replay_guard.lua` | `drivers/mame_guarded.sh` | the same log plus crash detection — authoritative (`-debug`, breakpoints on the vectors: `CRASH … REGS … STACK … END-CRASH`) or cheap (`CODE_RANGES` / `GUARD_MATCH`: `PCWEEDS` / `SOFTRESET`); the probe family (`GUARD_PROBE*`, `GUARD_BREAK`, `GUARD_TRACE`, `GUARD_PC_LOG`, `GUARD_FORCE`). Refuses `MASK_RANGES`: its log is unmasked and a masked expectation compared against it would be a phantom regression |
| `inp_guard.lua` | `bbh inp-play` | crash capture for a RECORDING's playback, no debugger (faithful timeslicing): a write tap on the machine's own exception store fires while the faulting frame is still on the stack |
| `snapshot_frames.lua` | (direct) | PNG snapshots at named frames — "look at it" as a scripted, rerunnable measurement |
| `trace_writes.lua` | (direct, `-debug`) | a debugger watchpoint over a range — hits with PC and registers; `WATCH`'s 4th field selects the address SPACE (a pc-relative read may go through the opcode space and a plain watchpoint is silently blind) |
| `tap_writes.lua` | (direct) | a non-debug PC-attributed WRITE tap (replay-exact frame counting); `REGLOG`, `STACKLOG`, the COLLECT mode |
| `read_tap.lua` | (direct) | a non-debug READ+WRITE tap — serialise a state-dependent value's writes and reads in ONE run (never correlate one across runs) |

Two things every instrument shares and a consumer copying one must keep:
INPUT STAGING IS CANONICAL — parse `held[fr]`, stage for the NEXT frame
(`held[frame + 1]`), so a frame number in any log IS a replay.lua frame
number (the lineage's ten `+1` deviants were one variant copied by every
later file until a census pinned the split); and a memory TAP is dropped
silently whenever the machine re-installs handlers in the space — every tap
script re-installs on the space's change notifier, or it logs boot writes
only and reads as "nobody writes this field".

## 4. The recording corpus (`bbh inp-play`, `bbh inp-corpus`)

The lineage's law: a field report is a RECORDING before it is a theory. A
win-fast rig never gives a CPU opponent the time to reach the script that
crashes; the maintainer's first hand-played recording found in an evening
what three sessions of rig-derived fixes had not. So: every reproducible
crash is captured as the emulator's own input recording with the fresh
nvram it started from, tracked under `[inp].corpus_dir/<name>/` with a
one-line NOTE, named `<what>-<freeze>-NN` after the freeze it was PLAYED on;
`bbh inp-corpus` replays every one under `inp_guard.lua` at every freeze and
fails on the first exception; a captured-but-unfixed crash is declared by a
DEFECT file naming the `vec<n> PC <pc6>` the gate then asserts (so the
capture cannot rot) and lists as OPEN. A playback that ran ZERO frames
executes no code and can raise no exception: `bbh inp-play` terminates a
log only when the emulator itself reports a playback of > 0 frames, the
corpus gate's liveness predicate rejects the rest, and the gate runs its
own controls on that predicate every time (`selftest/test_inp_corpus.sh`
exercises every verdict on a stub emulator).

## 5. What stayed with the lineage

`run_sim_jtcps2.sh` (the Verilator driver: jtframe-shaped, the download
offset, the per-core RAM-dump offset); every gate that names an address of
one game; the COLLECT mode's bucketing constants (now `COLLECT_STRIDE` /
`COLLECT_OFFSET` / `COLLECT_PORTED` in the environment, the lineage's values
documented in `tap_writes.lua`); the lineage's own `tests/lua/*.lua`, which
stay as they are (`harness_scope.md` §7.8: that tree never consumes this
harness).
